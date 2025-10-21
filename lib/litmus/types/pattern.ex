defmodule Litmus.Types.Pattern do
  @moduledoc """
  Pattern analysis utilities for extracting variables and types from patterns.

  This module provides functions to:
  - Extract variable bindings from patterns (tuples, lists, maps, structs, etc.)
  - Infer types for pattern-bound variables based on scrutinee types
  - Validate pattern types against expected types
  - Handle nested and compound patterns

  Patterns are represented as Elixir AST tuples:
  - Simple variable: `{:x, :_, nil}`
  - Tuple: `{:tuple, [count], [pattern1, pattern2, ...]}`
  - List: `[pattern1, pattern2, ...]` or `{:cons, _, [head, tail]}`
  - Map: `{:%, :_, [Map, [{key, pattern}, ...]]}`
  - Struct: `{:%, :_, [{:__aliases__, :_, [Module]}, [{key, pattern}, ...]]}`
  """

  @doc """
  Extract all variable names bound by a pattern.

  Recursively processes patterns to find all variables that would be bound
  by matching the pattern. Returns a list of atom variable names.

  Returns an empty list for patterns that don't bind variables (atoms, numbers,
  underscores, etc.).

  ## Examples

      iex> Litmus.Types.Pattern.extract_variables({:x, :_, nil})
      [:x]

      iex> Litmus.Types.Pattern.extract_variables(:_)
      []

      iex> Litmus.Types.Pattern.extract_variables({:tuple, [2], [{:a, :_, nil}, {:b, :_, nil}]})
      [:a, :b]
  """
  @spec extract_variables(term()) :: [atom()]
  def extract_variables(pattern) do
    do_extract_variables(pattern) |> Enum.uniq()
  end

  defp do_extract_variables({name, _, nil}) when is_atom(name) and name != :_ do
    [name]
  end

  defp do_extract_variables(:_), do: []

  # Underscores at position 0-2 (Elixir AST format)
  defp do_extract_variables({:_, _, _}), do: []

  # Simple terms (atoms, numbers, strings, etc.) - no bindings
  defp do_extract_variables(term) when is_atom(term) or is_number(term) or is_binary(term) do
    []
  end

  # Tuple patterns: {:tuple, _, elements}
  defp do_extract_variables({:tuple, _, elements}) when is_list(elements) do
    Enum.flat_map(elements, &do_extract_variables/1)
  end

  # List patterns (Elixir AST): [head | tail]
  defp do_extract_variables(list) when is_list(list) do
    Enum.flat_map(list, &do_extract_variables/1)
  end

  # Map patterns: {:%, _, [Map, fields]}
  defp do_extract_variables({:%, _, [_module, fields]}) when is_list(fields) do
    Enum.flat_map(fields, fn
      {_key, pattern} -> do_extract_variables(pattern)
      _ -> []
    end)
  end

  # Struct patterns: {:%, _, [StructModule, fields]}
  defp do_extract_variables({:%, _, [{:__aliases__, _, _}, fields]}) when is_list(fields) do
    Enum.flat_map(fields, fn
      {_key, pattern} -> do_extract_variables(pattern)
      _ -> []
    end)
  end

  # Cons pattern [head | tail]: {:cons, _, [head, tail]}
  defp do_extract_variables({:cons, _, [head, tail]}) do
    do_extract_variables(head) ++ do_extract_variables(tail)
  end

  # Guard pattern (when clause): {:when, _, [pattern, _guard]}
  defp do_extract_variables({:when, _, [pattern, _guard]}) do
    do_extract_variables(pattern)
  end

  # Binary patterns: {:<<>>, _, segments}
  defp do_extract_variables({:<<>>, _, segments}) when is_list(segments) do
    Enum.flat_map(segments, &do_extract_variables/1)
  end

  # Catch-all for unrecognized patterns
  defp do_extract_variables(_), do: []

  @doc """
  Infer a type for a pattern-bound variable based on the scrutinee type.

  Given a pattern and the type of the value being matched, returns the inferred
  type for variables bound in that pattern.

  Returns a map of variable names to their inferred types. If a type cannot be
  inferred, the variable maps to a fresh type variable.

  ## Examples

      iex> x_pat = {:x, :_, nil}
      iex> y_pat = {:y, :_, nil}
      iex> scrutinee_type = {:tuple, [2], [{:integer, []}, {:atom, []}]}
      iex> pattern = {:tuple, [2], [x_pat, y_pat]}
      iex> bindings = Litmus.Types.Pattern.infer_pattern_types(pattern, scrutinee_type)
      iex> bindings[:x]
      {:integer, []}
      iex> bindings[:y]
      {:atom, []}
  """
  @spec infer_pattern_types(term(), term()) :: %{atom() => term()}
  def infer_pattern_types(pattern, scrutinee_type) do
    do_infer_pattern_types(pattern, scrutinee_type) |> Enum.into(%{})
  end

  defp do_infer_pattern_types({name, _, nil}, type)
       when is_atom(name) and name != :_ do
    [{name, type}]
  end

  defp do_infer_pattern_types(:_, _type), do: []

  defp do_infer_pattern_types({:_, _, _}, _type), do: []

  # Tuple patterns destructure element types
  defp do_infer_pattern_types({:tuple, _, pattern_elements}, {:tuple, _, scrutinee_elements}) do
    Enum.zip_with([pattern_elements, scrutinee_elements], fn [pattern_elem, scrutinee_elem] ->
      do_infer_pattern_types(pattern_elem, scrutinee_elem)
    end)
    |> Enum.concat()
  end

  # List patterns - head gets element type
  defp do_infer_pattern_types(
         [{:cons, _, [head_pattern, _tail_pattern]}],
         {:list, [element_type]}
       ) do
    do_infer_pattern_types(head_pattern, element_type)
  end

  # List patterns [h|t] in AST form
  defp do_infer_pattern_types([head_pattern | tail_pattern], {:list, [element_type]}) do
    head_bindings = do_infer_pattern_types(head_pattern, element_type)
    tail_bindings = do_infer_pattern_types(tail_pattern, {:list, [element_type]})
    head_bindings ++ tail_bindings
  end

  # Map patterns
  defp do_infer_pattern_types({:%, _, [_module, fields]}, {:map, _field_types}) do
    Enum.flat_map(fields, fn
      {_key, pattern} ->
        # For maps, we don't have specific field types in the type system yet
        # So we assign a fresh type variable to each pattern
        do_infer_pattern_types(pattern, {:type_var, make_ref()})

      _ ->
        []
    end)
  end

  # Fallback: if we can't infer type, assign a fresh type variable
  defp do_infer_pattern_types(pattern, _scrutinee_type) do
    variables = do_extract_variables(pattern)

    Enum.map(variables, fn var ->
      {var, {:type_var, make_ref()}}
    end)
  end

  @doc """
  Check if a pattern is a simple variable (no destructuring).

  ## Examples

      iex> Litmus.Types.Pattern.simple_pattern?({:x, :_, nil})
      true

      iex> Litmus.Types.Pattern.simple_pattern?(:ok)
      true

      iex> Litmus.Types.Pattern.simple_pattern?({:tuple, :_, [{:a, :_, nil}]})
      false
  """
  @spec simple_pattern?(term()) :: boolean()
  def simple_pattern?({name, _, nil}) when is_atom(name), do: true
  def simple_pattern?(atom) when is_atom(atom), do: true
  def simple_pattern?(number) when is_number(number), do: true
  def simple_pattern?(binary) when is_binary(binary), do: true
  def simple_pattern?(_), do: false

  @doc """
  Check if a pattern is a complex pattern requiring destructuring.

  ## Examples

      iex> Litmus.Types.Pattern.complex_pattern?({:tuple, :_, [{:a, :_, nil}]})
      true

      iex> Litmus.Types.Pattern.complex_pattern?({:%, :_, [Map, []]})
      true

      iex> Litmus.Types.Pattern.complex_pattern?({:x, :_, nil})
      false
  """
  @spec complex_pattern?(term()) :: boolean()
  def complex_pattern?(pattern) do
    not simple_pattern?(pattern)
  end

  @doc """
  Extract variables from a list of patterns (multi-parameter case).

  Returns a list of variable names bound across all patterns.

  ## Examples

      iex> Litmus.Types.Pattern.extract_variables_from_list([{:x, :_, nil}, {:y, :_, nil}])
      [:x, :y]

      iex> Litmus.Types.Pattern.extract_variables_from_list([{:tuple, :_, [{:a, :_, nil}, {:b, :_, nil}]}, {:c, :_, nil}]) |> Enum.sort
      [:a, :b, :c]
  """
  @spec extract_variables_from_list([term()]) :: [atom()]
  def extract_variables_from_list(patterns) do
    patterns
    |> Enum.flat_map(&extract_variables/1)
    |> Enum.uniq()
  end

  @doc """
  Get the pattern name for display/error messages.

  ## Examples

      iex> Litmus.Types.Pattern.pattern_name({:x, :_, nil})
      "x"

      iex> Litmus.Types.Pattern.pattern_name({:tuple, :_, [{:a, :_, nil}]})
      "tuple"

      iex> Litmus.Types.Pattern.pattern_name(:ok)
      "ok"
  """
  @spec pattern_name(term()) :: String.t()
  def pattern_name({name, _, nil}) when is_atom(name), do: to_string(name)
  def pattern_name({:tuple, _, _}), do: "tuple"
  def pattern_name({:%, _, [Map, _]}), do: "map"

  # Struct pattern with fields: {:%, _, [{:__aliases__, _, parts}, fields]}
  def pattern_name({:%, _, [{:__aliases__, _, parts}, _]}) do
    parts |> List.last() |> to_string()
  end

  # Struct pattern without fields or map pattern
  def pattern_name({:%, _, _}), do: "struct"
  def pattern_name({:cons, _, _}), do: "list"
  def pattern_name(list) when is_list(list), do: "list"
  def pattern_name({:<<>>, _, _}), do: "binary"
  def pattern_name(atom) when is_atom(atom), do: to_string(atom)
  def pattern_name(num) when is_number(num), do: to_string(num)
  def pattern_name(str) when is_binary(str), do: "\"#{str}\""
  def pattern_name(_), do: "pattern"

  @doc """
  Extract pattern and guard from a guard pattern.

  Guard patterns have the form `{:when, _, [pattern, guard]}`.
  Simple patterns without guards are returned as-is.

  Returns a tuple `{pattern, guard}` where guard is nil if no guard present.
  """
  @spec extract_guard(term()) :: {term(), term() | nil}
  def extract_guard({:when, _, [pattern, guard]}) do
    {pattern, guard}
  end

  def extract_guard(pattern) do
    {pattern, nil}
  end

  @doc """
  Analyze a pattern for case clause context creation.

  Returns pattern variables with their inferred types based on scrutinee type.
  The caller is responsible for adding these to the context.
  """
  @spec analyze_pattern(term(), term()) :: %{atom() => term()}
  def analyze_pattern(pattern, scrutinee_type) do
    infer_pattern_types(pattern, scrutinee_type)
  end

  @doc """
  Analyze a guard expression to extract bound variables.

  Guards can reference variables from the pattern for filtering.
  Returns the list of variable names referenced in the guard expression.
  """
  @spec guard_bindings(term()) :: [atom()]
  def guard_bindings(guard) do
    guard
    |> extract_variables()
    |> Enum.uniq()
  end

  @doc """
  Determine if a guard expression can potentially throw an exception.

  Built-in guard functions and operations are pure and cannot throw.
  Custom function calls in guards may raise exceptions.

  Returns true if the guard might throw an exception.
  """
  @spec guard_can_throw?(term()) :: boolean()
  def guard_can_throw?({:when, _, [_pattern, guard]}) do
    guard_can_throw?(guard)
  end

  # Comparison operators - pure, cannot throw
  def guard_can_throw?({:>, _, _}), do: false
  def guard_can_throw?({:<, _, _}), do: false
  def guard_can_throw?({:>=, _, _}), do: false
  def guard_can_throw?({:==, _, _}), do: false

  # Boolean operators - check both sides
  def guard_can_throw?({:and, _, [left, right]}) do
    guard_can_throw?(left) or guard_can_throw?(right)
  end

  def guard_can_throw?({:or, _, [left, right]}) do
    guard_can_throw?(left) or guard_can_throw?(right)
  end

  def guard_can_throw?({:not, _, [expr]}) do
    guard_can_throw?(expr)
  end

  # Built-in type check functions - pure, cannot throw
  def guard_can_throw?({func, _, _args})
      when func in [:is_atom, :is_binary, :is_bitstring, :is_boolean, :is_float,
                    :is_function, :is_integer, :is_list, :is_map, :is_number,
                    :is_pid, :is_port, :is_reference, :is_tuple] do
    false
  end

  # Other built-in guard functions that cannot throw
  def guard_can_throw?({func, _, _args})
      when func in [:length, :hd, :tl, :abs, :round, :floor, :ceil, :trunc] do
    # Note: These can fail at runtime but don't throw exceptions in guard context
    false
  end

  # Custom function calls - conservative: assume they can throw
  def guard_can_throw?({_func, _, _args}) do
    true
  end

  # Variables, atoms, literals - cannot throw
  def guard_can_throw?(_) do
    false
  end
end
