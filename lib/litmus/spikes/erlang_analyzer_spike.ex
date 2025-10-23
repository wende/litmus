defmodule Litmus.Spikes.ErlangAnalyzerSpike do
  @moduledoc """
  Technical spike to test the feasibility of analyzing Erlang modules from their abstract format.

  This module answers three critical questions:
  1. Can we extract and parse Erlang abstract format from BEAM files?
  2. Can we correctly classify pure vs impure Erlang functions?
  3. Can we handle Erlang-specific constructs (receive, !, spawn)?

  ## Success Criteria
  - Parse 50+ common Erlang stdlib functions
  - Achieve 90%+ accuracy in purity classification
  - Handle all major Erlang effect-producing constructs

  ## If Success
  - Integrate Erlang analysis into main ASTWalker pipeline
  - Build comprehensive Erlang stdlib registry

  ## If Failure
  - Use pre-built whitelist approach only
  - Mark unknown Erlang functions as :unknown conservatively
  """

  @doc """
  Known effects for Erlang Built-In Functions (BIFs).

  BIFs are implemented in C and cannot be analyzed from abstract code.
  These must be manually classified based on their documented behavior.
  """
  @erlang_bif_effects %{
    # Pure arithmetic and data operations
    {:erlang, :abs, 1} => :p,
    {:erlang, :+, 2} => :p,
    {:erlang, :-, 2} => :p,
    {:erlang, :*, 2} => :p,
    {:erlang, :div, 2} => :p,
    {:erlang, :rem, 2} => :p,
    {:erlang, :band, 2} => :p,
    {:erlang, :bor, 2} => :p,
    {:erlang, :bxor, 2} => :p,
    {:erlang, :bnot, 1} => :p,

    # Pure tuple operations
    {:erlang, :element, 2} => :p,
    {:erlang, :setelement, 3} => :p,
    {:erlang, :tuple_size, 1} => :p,
    {:erlang, :tuple_to_list, 1} => :p,
    {:erlang, :list_to_tuple, 1} => :p,
    {:erlang, :make_tuple, 2} => :p,
    {:erlang, :make_tuple, 3} => :p,

    # Pure list operations
    {:erlang, :hd, 1} => :p,
    {:erlang, :tl, 1} => :p,
    {:erlang, :length, 1} => :p,
    {:erlang, :++, 2} => :p,
    {:erlang, :--, 2} => :p,

    # Pure binary operations
    {:erlang, :byte_size, 1} => :p,
    {:erlang, :bit_size, 1} => :p,
    {:erlang, :binary_to_list, 1} => :p,
    {:erlang, :list_to_binary, 1} => :p,

    # Pure atom/string operations
    {:erlang, :atom_to_list, 1} => :p,
    {:erlang, :list_to_atom, 1} => :p,
    {:erlang, :atom_to_binary, 2} => :p,
    {:erlang, :binary_to_atom, 2} => :p,
    {:erlang, :integer_to_list, 1} => :p,
    {:erlang, :list_to_integer, 1} => :p,
    {:erlang, :float_to_list, 1} => :p,
    {:erlang, :list_to_float, 1} => :p,

    # Pure comparison
    {:erlang, :==, 2} => :p,
    {:erlang, :"/=", 2} => :p,
    {:erlang, :<, 2} => :p,
    {:erlang, :>, 2} => :p,
    {:erlang, :"=<", 2} => :p,
    {:erlang, :>=, 2} => :p,
    {:erlang, :"=:=", 2} => :p,
    {:erlang, :"=/=", 2} => :p,

    # Pure map operations
    {:erlang, :map_size, 1} => :p,
    {:erlang, :map_get, 2} => :p,
    {:erlang, :is_map_key, 2} => :p,

    # Pure error functions (raise but don't do I/O)
    {:erlang, :error, 1} => :p,
    {:erlang, :error, 2} => :p,
    {:erlang, :throw, 1} => :p,

    # Pure apply (depends on what's being applied)
    {:erlang, :apply, 2} => :p,
    {:erlang, :apply, 3} => :p,

    # Pure type checks
    {:erlang, :is_atom, 1} => :p,
    {:erlang, :is_binary, 1} => :p,
    {:erlang, :is_boolean, 1} => :p,
    {:erlang, :is_float, 1} => :p,
    {:erlang, :is_function, 1} => :p,
    {:erlang, :is_integer, 1} => :p,
    {:erlang, :is_list, 1} => :p,
    {:erlang, :is_number, 1} => :p,
    {:erlang, :is_pid, 1} => :p,
    {:erlang, :is_port, 1} => :p,
    {:erlang, :is_reference, 1} => :p,
    {:erlang, :is_tuple, 1} => :p,
    {:erlang, :is_map, 1} => :p,

    # Process operations (side effects)
    {:erlang, :spawn, 1} => :s,
    {:erlang, :spawn, 2} => :s,
    {:erlang, :spawn, 3} => :s,
    {:erlang, :spawn, 4} => :s,
    {:erlang, :spawn_link, 1} => :s,
    {:erlang, :spawn_link, 2} => :s,
    {:erlang, :spawn_link, 3} => :s,
    {:erlang, :spawn_link, 4} => :s,
    {:erlang, :spawn_monitor, 1} => :s,
    {:erlang, :spawn_monitor, 3} => :s,
    {:erlang, :send, 2} => :s,
    {:erlang, :!, 2} => :s,
    {:erlang, :exit, 1} => :s,
    {:erlang, :exit, 2} => :s,
    {:erlang, :link, 1} => :s,
    {:erlang, :unlink, 1} => :s,
    {:erlang, :monitor, 2} => :s,
    {:erlang, :demonitor, 1} => :s,
    {:erlang, :process_flag, 2} => :s,
    {:erlang, :register, 2} => :s,
    {:erlang, :unregister, 1} => :s,

    # Environment-dependent (reads process/node state)
    {:erlang, :self, 0} => :d,
    {:erlang, :node, 0} => :d,
    {:erlang, :node, 1} => :d,
    {:erlang, :nodes, 0} => :d,
    {:erlang, :nodes, 1} => :d,
    {:erlang, :now, 0} => :d,
    {:erlang, :system_time, 0} => :d,
    {:erlang, :system_time, 1} => :d,
    {:erlang, :monotonic_time, 0} => :d,
    {:erlang, :monotonic_time, 1} => :d,
    {:erlang, :timestamp, 0} => :d,
    {:erlang, :unique_integer, 0} => :d,
    {:erlang, :unique_integer, 1} => :d,
    {:erlang, :make_ref, 0} => :d,
    {:erlang, :get, 0} => :d,
    {:erlang, :get, 1} => :d,
    {:erlang, :get_keys, 0} => :d,
    {:erlang, :get_keys, 1} => :d,
    {:erlang, :process_info, 1} => :d,
    {:erlang, :process_info, 2} => :d,
    {:erlang, :processes, 0} => :d,
    {:erlang, :registered, 0} => :d,
    {:erlang, :whereis, 1} => :d,

    # Process dictionary (side effects)
    {:erlang, :put, 2} => :s,
    {:erlang, :erase, 0} => :s,
    {:erlang, :erase, 1} => :s,

    # I/O (side effects)
    {:erlang, :display, 1} => :s,
    {:erlang, :halt, 0} => :s,
    {:erlang, :halt, 1} => :s
  }

  @doc """
  Known effects for common Erlang stdlib modules.

  These classifications are used when a module call is detected.
  Individual function analysis may override these defaults.
  """
  @erlang_module_effects %{
    # Pure modules (data structure operations)
    lists: :p,
    maps: :p,
    proplists: :p,
    ordsets: :p,
    orddict: :p,
    string: :p,
    binary: :p,
    sets: :p,
    gb_sets: :p,
    gb_trees: :p,
    array: :p,
    queue: :p,
    dict: :p,
    calendar: :p,
    unicode: :p,

    # I/O modules (side effects)
    io: :s,
    io_lib: :p,
    # io_lib is pure string formatting
    file: :s,

    # State/table modules (side effects)
    ets: :s,
    dets: :s,
    mnesia: :s,

    # Process/OTP modules (side effects)
    gen_server: :s,
    gen_fsm: :s,
    gen_statem: :s,
    gen_event: :s,
    supervisor: :s,
    application: :s,
    proc_lib: :s,

    # Timer (side effects)
    timer: :s,

    # Code/system (side effects or dependent)
    code: :s,
    init: :s,
    error_logger: :s,
    logger: :s,

    # Mixed purity - handle per-function
    # For now, mark as dependent (conservative)
    erlang: :d
  }

  @doc """
  Analyzes an Erlang module and classifies all its functions.

  Returns `{:ok, results}` where results is a map of {module, function, arity} => effect
  or `{:error, reason}`.
  """
  def analyze_erlang_module(module) when is_atom(module) do
    with {:ok, forms} <- extract_erlang_forms(module) do
      # Find all function definitions
      functions = extract_function_definitions(forms)

      # Classify each function
      results =
        Enum.reduce(functions, %{}, fn {name, arity}, acc ->
          effect = classify_erlang_function(forms, name, arity)
          Map.put(acc, {module, name, arity}, effect)
        end)

      {:ok, results}
    end
  end

  @doc """
  Extracts abstract code forms from an Erlang module's BEAM file.

  Returns `{:ok, forms}` or `{:error, reason}`.
  """
  def extract_erlang_forms(module) when is_atom(module) do
    case :code.get_object_code(module) do
      {^module, beam_binary, _filename} ->
        extract_forms_from_beam(beam_binary, module)

      :error ->
        {:error, :module_not_found}
    end
  end

  defp extract_forms_from_beam(beam_binary, module) do
    case :beam_lib.chunks(beam_binary, [:abstract_code]) do
      {:ok, {^module, [abstract_code: {:raw_abstract_v1, forms}]}} ->
        {:ok, forms}

      {:ok, {^module, [abstract_code: :no_abstract_code]}} ->
        {:error, :no_abstract_code}

      {:error, :beam_lib, reason} ->
        {:error, {:beam_lib_error, reason}}
    end
  end

  @doc """
  Extracts all function definitions from Erlang abstract forms.

  Returns a list of {function_name, arity} tuples.
  """
  def extract_function_definitions(forms) do
    forms
    |> Enum.filter(fn
      {:function, _line, _name, _arity, _clauses} -> true
      _ -> false
    end)
    |> Enum.map(fn {:function, _line, name, arity, _clauses} ->
      {name, arity}
    end)
    |> Enum.uniq()
  end

  @doc """
  Classifies an Erlang function by analyzing its abstract forms.

  Returns an effect type: :p (pure), :s (side effects), :d (dependent), :l (lambda), or :u (unknown)
  """
  def classify_erlang_function(forms, func_name, arity) do
    # Find the function definition
    function_forms =
      Enum.filter(forms, fn
        {:function, _line, ^func_name, ^arity, _clauses} -> true
        _ -> false
      end)

    case function_forms do
      [] ->
        :u

      # Unknown - function not found
      [{:function, _line, _name, _arity, clauses}] ->
        # Analyze all clauses
        effects =
          clauses
          |> Enum.flat_map(&analyze_clause/1)
          |> Enum.uniq()

        classify_effects(effects)
    end
  end

  defp analyze_clause({:clause, _line, _args, _guards, body}) do
    # Note: Guards are treated the same as patterns (user feedback)
    # They can fail but don't have side effects
    Enum.flat_map(body, &detect_effects/1)
  end

  @doc """
  Detects effects in an Erlang abstract form.

  Returns a list of detected effect types.
  """
  def detect_effects(form) do
    case form do
      # Receive block = side effects (message passing)
      {:receive, _line, _clauses, _after_clause} ->
        [:side_effects]

      # Send operator ! = side effects
      {:op, _line, :'!', _dest, _msg} ->
        [:side_effects]

      # Spawn operations = side effects
      {:call, _line, {:atom, _l, :spawn}, _args} ->
        [:side_effects]

      {:call, _line, {:atom, _l, :spawn_link}, _args} ->
        [:side_effects]

      {:call, _line, {:atom, _l, :spawn_monitor}, _args} ->
        [:side_effects]

      # Remote call to erlang module (BIF check)
      {:call, _line, {:remote, _l1, {:atom, _l2, :erlang}, {:atom, _l3, func}}, args} ->
        bif_effects(:erlang, func, length(args))

      # Remote call to other module
      {:call, _line, {:remote, _l1, {:atom, _l2, mod}, {:atom, _l3, _func}}, _args} ->
        module_effects(mod)

      # Local call - cannot determine without context
      {:call, _line, {:atom, _l, _func}, _args} ->
        # Local calls are analyzed recursively, so we mark as unknown here
        [:local_call]

      # Match expression - analyze both pattern and expression
      {:match, _line, _pattern, expr} ->
        detect_effects(expr)

      # Case expression - analyze all branches
      {:case, _line, expr, clauses} ->
        expr_effects = detect_effects(expr)

        clause_effects =
          Enum.flat_map(clauses, fn {:clause, _l, _patterns, _guards, body} ->
            Enum.flat_map(body, &detect_effects/1)
          end)

        expr_effects ++ clause_effects

      # If expression - analyze all branches
      {:if, _line, clauses} ->
        Enum.flat_map(clauses, fn
          {:clause, _l, [], _guards, body} ->
            # Guards in 'if' are in position 4 (guards), body in position 5
            Enum.flat_map(body, &detect_effects/1)

          _ ->
            []
        end)

      # Try expression - analyze body and handlers
      {:try, _line, body, [], catch_clauses, after_body} ->
        body_effects = Enum.flat_map(body, &detect_effects/1)

        catch_effects =
          Enum.flat_map(catch_clauses, fn {:clause, _l, _patterns, _guards, handler_body} ->
            Enum.flat_map(handler_body, &detect_effects/1)
          end)

        after_effects = Enum.flat_map(after_body, &detect_effects/1)

        body_effects ++ catch_effects ++ after_effects

      # Block of expressions
      {:block, _line, exprs} ->
        Enum.flat_map(exprs, &detect_effects/1)

      # Tuple - analyze all elements
      {:tuple, _line, elements} ->
        Enum.flat_map(elements, &detect_effects/1)

      # List cons - analyze head and tail
      {:cons, _line, head, tail} ->
        detect_effects(head) ++ detect_effects(tail)

      # Binary construction - analyze segments
      {:bin, _line, elements} ->
        Enum.flat_map(elements, fn
          {:bin_element, _l, expr, _size, _tsl} -> detect_effects(expr)
        end)

      # Map - analyze all values
      {:map, _line, pairs} ->
        Enum.flat_map(pairs, fn
          {:map_field_assoc, _l, _key, value} -> detect_effects(value)
          {:map_field_exact, _l, _key, value} -> detect_effects(value)
        end)

      # Map update - analyze base map and updates
      {:map, _line, base, pairs} ->
        base_effects = detect_effects(base)

        pair_effects =
          Enum.flat_map(pairs, fn
            {:map_field_assoc, _l, _key, value} -> detect_effects(value)
            {:map_field_exact, _l, _key, value} -> detect_effects(value)
          end)

        base_effects ++ pair_effects

      # Operator - analyze operands
      {:op, _line, _op, left, right} ->
        detect_effects(left) ++ detect_effects(right)

      {:op, _line, _op, operand} ->
        detect_effects(operand)

      # Record operations - analyze fields
      {:record, _line, _name, fields} ->
        Enum.flat_map(fields, fn
          {:record_field, _l, _field, value} -> detect_effects(value)
        end)

      {:record, _line, base, _name, fields} ->
        base_effects = detect_effects(base)

        field_effects =
          Enum.flat_map(fields, fn
            {:record_field, _l, _field, value} -> detect_effects(value)
          end)

        base_effects ++ field_effects

      # Literals and atoms - no effects
      {:atom, _line, _value} ->
        []

      {:integer, _line, _value} ->
        []

      {:float, _line, _value} ->
        []

      {:string, _line, _value} ->
        []

      {:char, _line, _value} ->
        []

      {:nil, _line} ->
        []

      # Variable - no effects
      {:var, _line, _name} ->
        []

      # Function clause (anonymous function) - analyze body
      {:fun, _line, {:clauses, clauses}} ->
        Enum.flat_map(clauses, &analyze_clause/1)

      # Named function reference - check if it's a BIF
      {:fun, _line, {:function, {:atom, _l1, mod}, {:atom, _l2, func}, {:integer, _l3, arity}}} ->
        case {mod, func, arity} do
          {:erlang, f, a} -> bif_effects(:erlang, f, a)
          {m, _f, _a} -> module_effects(m)
        end

      # Catch expression - analyze body
      {:catch, _line, expr} ->
        detect_effects(expr)

      # List comprehension - analyze template and generators
      {:lc, _line, template, qualifiers} ->
        template_effects = detect_effects(template)

        qualifier_effects =
          Enum.flat_map(qualifiers, fn
            {:generate, _l, _pattern, expr} -> detect_effects(expr)
            {:b_generate, _l, _pattern, expr} -> detect_effects(expr)
            expr -> detect_effects(expr)
          end)

        template_effects ++ qualifier_effects

      # Binary comprehension
      {:bc, _line, template, qualifiers} ->
        template_effects = detect_effects(template)

        qualifier_effects =
          Enum.flat_map(qualifiers, fn
            {:generate, _l, _pattern, expr} -> detect_effects(expr)
            {:b_generate, _l, _pattern, expr} -> detect_effects(expr)
            expr -> detect_effects(expr)
          end)

        template_effects ++ qualifier_effects

      # Unknown form - conservative
      _ ->
        []
    end
  end

  @doc """
  Returns effect classification for an Erlang BIF.
  """
  def bif_effects(mod, func, arity) do
    case @erlang_bif_effects[{mod, func, arity}] do
      :p -> []
      :s -> [:side_effects]
      :d -> [:dependent]
      # Unlisted BIF - mark as unknown (conservative)
      nil -> [:unknown_bif]
    end
  end

  @doc """
  Returns effect classification for an Erlang module.
  """
  def module_effects(mod) do
    case @erlang_module_effects[mod] do
      :p -> []
      :s -> [:side_effects]
      :d -> [:dependent]
      # Unlisted module - assume pure (optimistic for data structures)
      nil -> []
    end
  end

  @doc """
  Classifies a list of detected effects into a single effect type.

  Priority (most severe first):
  1. Unknown effects (conservative)
  2. Side effects
  3. Dependent on environment
  4. Lambda (higher-order)
  5. Pure
  """
  def classify_effects(effects) do
    effects = Enum.uniq(effects)

    cond do
      :unknown_bif in effects -> :u
      :side_effects in effects -> :s
      :dependent in effects -> :d
      :lambda in effects -> :l
      # Local calls don't affect purity if no other effects
      :local_call in effects -> :p
      true -> :p
    end
  end

  @doc """
  Checks if an Erlang module is a NIF module.

  NIFs cannot be analyzed from abstract code.
  """
  def is_nif?(module) when is_atom(module) do
    case extract_erlang_forms(module) do
      {:ok, _forms} -> false
      {:error, :no_abstract_code} -> :maybe
      {:error, _} -> :maybe
    end
  end
end
