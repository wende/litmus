defmodule Litmus.Types.Substitution do
  @moduledoc """
  Type substitution operations for the type system.

  Substitutions map type and effect variables to their concrete types/effects.
  This is essential for type inference and instantiation.
  """

  alias Litmus.Types.Core
  alias Litmus.Formatter

  @type t :: %{(Core.type_var() | Core.effect_var()) => Core.elixir_type() | Core.effect_type()}

  @doc """
  Creates an empty substitution.
  """
  def empty, do: %{}

  @doc """
  Adds a new substitution mapping.

  ## Examples

      iex> empty() |> add({:type_var, :a}, :int)
      %{{:type_var, :a} => :int}
  """
  def add(subst, var, type) do
    Map.put(subst, var, type)
  end

  @doc """
  Applies a substitution to a type.

  Recursively replaces all variables with their substituted values.

  ## Examples

      iex> subst = %{{:type_var, :a} => :int}
      iex> apply_subst(subst, {:type_var, :a})
      :int

      iex> apply_subst(subst, {:list, {:type_var, :a}})
      {:list, :int}
  """
  def apply_subst(subst, type) when map_size(subst) == 0, do: type

  def apply_subst(subst, type) do
    case type do
      # Variables - look up in substitution
      {:type_var, _} = var ->
        case Map.get(subst, var) do
          nil -> var
          substituted -> apply_subst(subst, substituted)  # Apply transitively
        end

      {:effect_var, _} = var ->
        case Map.get(subst, var) do
          nil -> var
          substituted -> apply_subst(subst, substituted)  # Apply transitively
        end

      # Compound types - apply recursively
      {:function, arg, effect, ret} ->
        {:function,
         apply_subst(subst, arg),
         apply_subst(subst, effect),
         apply_subst(subst, ret)}

      {:tuple, types} ->
        {:tuple, Enum.map(types, &apply_subst(subst, &1))}

      {:list, elem_type} ->
        {:list, apply_subst(subst, elem_type)}

      {:map, pairs} ->
        {:map, Enum.map(pairs, fn {k, v} -> {apply_subst(subst, k), apply_subst(subst, v)} end)}

      {:union, types} ->
        {:union, Enum.map(types, &apply_subst(subst, &1))}

      {:forall, vars, body} ->
        # Remove bound variables from substitution before applying to body
        filtered_subst = Enum.reject(subst, fn {var, _} -> var in vars end) |> Enum.into(%{})
        {:forall, vars, apply_subst(filtered_subst, body)}

      # Effect types
      {:effect_row, label, tail} ->
        {:effect_row, label, apply_subst(subst, tail)}

      # Base cases - no substitution needed
      _ ->
        type
    end
  end

  @doc """
  Composes two substitutions.

  The resulting substitution applies s1 then s2.

  ## Examples

      iex> s1 = %{{:type_var, :a} => {:type_var, :b}}
      iex> s2 = %{{:type_var, :b} => :int}
      iex> compose(s1, s2)
      %{{:type_var, :a} => :int, {:type_var, :b} => :int}
  """
  def compose(s1, s2) when map_size(s1) == 0, do: s2
  def compose(s1, s2) when map_size(s2) == 0, do: s1

  def compose(s1, s2) do
    # Apply s2 to all values in s1
    s1_updated = Map.new(s1, fn {var, type} -> {var, apply_subst(s2, type)} end)

    # Add mappings from s2 that aren't in s1
    Map.merge(s2, s1_updated)
  end

  @doc """
  Applies a substitution to a typing environment.

  The environment maps variable names to types.
  """
  def apply_to_env(subst, env) when map_size(subst) == 0, do: env

  def apply_to_env(subst, env) do
    Map.new(env, fn {name, type} -> {name, apply_subst(subst, type)} end)
  end

  @doc """
  Restricts a substitution to only the given variables.
  """
  def restrict(subst, vars) do
    Map.filter(subst, fn {var, _} -> var in vars end)
  end

  @doc """
  Removes the given variables from a substitution.
  """
  def remove(subst, vars) do
    Map.reject(subst, fn {var, _} -> var in vars end)
  end

  @doc """
  Gets all variables in the domain of a substitution.
  """
  def domain(subst) do
    Map.keys(subst) |> MapSet.new()
  end

  @doc """
  Gets all free variables in the range of a substitution.
  """
  def range_vars(subst) do
    subst
    |> Map.values()
    |> Enum.flat_map(&Core.free_variables/1)
    |> MapSet.new()
  end

  @doc """
  Checks if a substitution is idempotent.

  A substitution is idempotent if applying it twice gives the same result as applying it once.
  This happens when no variable in the domain appears in the range.
  """
  def idempotent?(subst) do
    domain_vars = domain(subst)
    range_variables = range_vars(subst)
    MapSet.disjoint?(domain_vars, range_variables)
  end

  @doc """
  Makes a substitution idempotent by applying it to its own range.
  """
  def make_idempotent(subst) do
    if idempotent?(subst) do
      subst
    else
      # Apply substitution to its own values until fixed point
      new_subst = Map.new(subst, fn {var, type} -> {var, apply_subst(subst, type)} end)
      if new_subst == subst do
        subst
      else
        make_idempotent(new_subst)
      end
    end
  end

  @doc """
  Pretty prints a substitution for debugging.
  """
  def format(subst) do
    if map_size(subst) == 0 do
      "∅"
    else
      subst
      |> Enum.map(fn {var, type} ->
        "#{Formatter.format_var(var)} ↦ #{Formatter.format_type(type)}"
      end)
      |> Enum.join(", ")
      |> then(&"[#{&1}]")
    end
  end
end