defmodule Litmus.Types.Core do
  @moduledoc """
  Core type definitions for the Litmus type and effect system.

  Based on row-polymorphic effects with duplicate labels as described
  in the research, enabling principal type inference without complex
  auxiliary mechanisms.

  ## Type System Overview

  - Types: τ ::= α | Int | String | Bool | τ₁ → ε τ₂ | {τ₁, ..., τₙ} | [τ]
  - Effects: ε ::= ⟨⟩ | ⟨l⟩ | ⟨l | ε⟩ | μ (effect variable)
  - Labels: l ::= exn | io | state | process | ...

  The key innovation is allowing duplicate labels in effect rows,
  which enables proper handling of nested effect contexts.
  """

  @type type_var :: {:type_var, atom()}
  @type effect_var :: {:effect_var, atom()}

  # Basic types
  @type primitive_type ::
          :int | :float | :string | :bool | :atom | :pid | :reference | :any

  # Type definitions
  @type elixir_type ::
          primitive_type()
          | type_var()
          | {:function, elixir_type(), effect_type(), elixir_type()}
          | {:tuple, list(elixir_type())}
          | {:list, elixir_type()}
          | {:map, list({elixir_type(), elixir_type()})}
          | {:union, list(elixir_type())}
          | {:forall, list(type_var() | effect_var()), elixir_type()}

  # Effect types using row polymorphism
  # No effects
  @type effect_label ::
          :pure
          # Can raise exceptions
          | :exn
          # I/O operations
          | :io
          # File system operations
          | :file
          # Process operations (spawn, send, receive)
          | :process
          # Stateful operations
          | :state
          # Native implemented functions
          | :nif
          # Network operations
          | :network
          # ETS table operations
          | :ets
          # Time-dependent operations
          | :time
          # Random number generation
          | :random
          # Unknown effect (for gradual typing)
          | :unknown

  # ⟨⟩ - pure
  @type effect_type ::
          {:effect_empty}
          # ⟨l⟩ - single effect
          | {:effect_label, effect_label()}
          # ⟨l | ε⟩ - row extension
          | {:effect_row, effect_label(), effect_type()}
          # μ - effect variable
          | effect_var()
          # ¿ - unknown (gradual)
          | {:effect_unknown}

  @doc """
  Creates an empty effect (pure).

  ## Examples

      iex> alias Litmus.Types.Core
      iex> Core.empty_effect()
      {:effect_empty}
  """
  def empty_effect, do: {:effect_empty}

  @doc """
  Creates a single effect label.

  ## Examples

      iex> alias Litmus.Types.Core
      iex> Core.single_effect(:io)
      {:effect_label, :io}
  """
  def single_effect(label) when is_atom(label) do
    {:effect_label, label}
  end

  @doc """
  Extends an effect row with a new label.

  Allows duplicate labels for proper nesting.

  ## Examples

      iex> alias Litmus.Types.Core
      iex> Core.extend_effect(:exn, Core.empty_effect())
      {:effect_row, :exn, {:effect_empty}}

      iex> alias Litmus.Types.Core
      iex> Core.extend_effect(:io, Core.single_effect(:exn))
      {:effect_row, :io, {:effect_label, :exn}}
  """
  def extend_effect(label, tail) when is_atom(label) do
    {:effect_row, label, tail}
  end

  @doc """
  Creates a function type with effects.

  ## Examples

      iex> alias Litmus.Types.Core
      iex> Core.function_type(:int, Core.single_effect(:io), :string)
      {:function, :int, {:effect_label, :io}, :string}
  """
  def function_type(arg_type, effect, return_type) do
    {:function, arg_type, effect, return_type}
  end

  @doc """
  Creates a polymorphic type with quantified variables.

  ## Examples

      iex> alias Litmus.Types.Core
      iex> Core.forall_type([{:type_var, :a}], {:type_var, :a})
      {:forall, [{:type_var, :a}], {:type_var, :a}}
  """
  def forall_type(vars, body) when is_list(vars) do
    {:forall, vars, body}
  end

  @doc """
  Checks if a type is monomorphic (contains no type variables).
  """
  def monomorphic?(type) do
    !contains_variables?(type)
  end

  defp contains_variables?({:type_var, _}), do: true
  defp contains_variables?({:effect_var, _}), do: true

  defp contains_variables?({:function, arg, effect, ret}) do
    contains_variables?(arg) or contains_variables?(effect) or contains_variables?(ret)
  end

  defp contains_variables?({:tuple, types}) do
    Enum.any?(types, &contains_variables?/1)
  end

  defp contains_variables?({:list, type}) do
    contains_variables?(type)
  end

  defp contains_variables?({:map, pairs}) do
    Enum.any?(pairs, fn {k, v} -> contains_variables?(k) or contains_variables?(v) end)
  end

  defp contains_variables?({:union, types}) do
    Enum.any?(types, &contains_variables?/1)
  end

  defp contains_variables?({:forall, _, body}) do
    contains_variables?(body)
  end

  defp contains_variables?({:effect_row, _, tail}) do
    contains_variables?(tail)
  end

  defp contains_variables?(_), do: false

  @doc """
  Collects all free type and effect variables in a type.
  """
  def free_variables(type, bound \\ MapSet.new()) do
    case type do
      {:type_var, name} ->
        if MapSet.member?(bound, name) do
          MapSet.new()
        else
          MapSet.new([{:type_var, name}])
        end

      {:effect_var, name} ->
        if MapSet.member?(bound, name) do
          MapSet.new()
        else
          MapSet.new([{:effect_var, name}])
        end

      {:function, arg, effect, ret} ->
        MapSet.union(
          free_variables(arg, bound),
          MapSet.union(
            free_variables(effect, bound),
            free_variables(ret, bound)
          )
        )

      {:tuple, types} ->
        types
        |> Enum.map(&free_variables(&1, bound))
        |> Enum.reduce(MapSet.new(), &MapSet.union/2)

      {:list, type} ->
        free_variables(type, bound)

      {:map, pairs} ->
        pairs
        |> Enum.flat_map(fn {k, v} -> [free_variables(k, bound), free_variables(v, bound)] end)
        |> Enum.reduce(MapSet.new(), &MapSet.union/2)

      {:union, types} ->
        types
        |> Enum.map(&free_variables(&1, bound))
        |> Enum.reduce(MapSet.new(), &MapSet.union/2)

      {:forall, vars, body} ->
        new_bound =
          Enum.reduce(vars, bound, fn
            {:type_var, name}, acc -> MapSet.put(acc, name)
            {:effect_var, name}, acc -> MapSet.put(acc, name)
            _, acc -> acc
          end)

        free_variables(body, new_bound)

      {:effect_row, _label, tail} ->
        free_variables(tail, bound)

      _ ->
        MapSet.new()
    end
  end

  @doc """
  Converts an effect to compact PURITY library format.

  Returns one of:
  - `:p` - pure (no effects)
  - `{:d, [MFA list]}` - dependent (reads from execution environment) with specific function tracking
  - `:d` - dependent (old-style, for compatibility)
  - `:l` - lambda (effects depend on passed lambdas)
  - `:n` - nif
  - `{:e, [exception_types]}` - can raise exceptions
  - `{:s, [MFA list]}` - side effects with specific function tracking
  - `:u` - unknown

  ## Examples

      iex> alias Litmus.Types.Core
      iex> Core.to_compact_effect({:effect_empty})
      :p

      iex> alias Litmus.Types.Core
      iex> Core.to_compact_effect({:effect_label, :exn})
      {:e, [:exn]}

      iex> alias Litmus.Types.Core
      iex> Core.to_compact_effect({:s, ["File.read/1"]})
      {:s, ["File.read/1"]}

      iex> alias Litmus.Types.Core
      iex> Core.to_compact_effect({:s, ["File.read/1", "IO.puts/1"]})
      {:s, ["File.read/1", "IO.puts/1"]}

      iex> alias Litmus.Types.Core
      iex> Core.to_compact_effect({:d, ["System.get_env/1"]})
      {:d, ["System.get_env/1"]}

      iex> alias Litmus.Types.Core
      iex> Core.to_compact_effect({:d, ["System.get_env/1", "Process.get/1"]})
      {:d, ["System.get_env/1", "Process.get/1"]}
  """
  def to_compact_effect(effect) do
    labels = extract_effect_labels(effect)

    cond do
      # Pure - no effects
      labels == [] ->
        :p

      # Contains NIF
      :nif in labels ->
        :n

      # Has specific side effects tracked with MFAs (prioritize over unknown)
      has_side_effect_mfas?(labels) ->
        # Extract all side effect MFAs and combine them
        mfas =
          Enum.flat_map(labels, fn
            {:s, list} -> list
            _ -> []
          end)

        {:s, mfas}

      # Has specific dependent effects tracked with MFAs (prioritize over unknown)
      has_dependent_effect_mfas?(labels) ->
        # Extract all dependent effect MFAs and combine them
        mfas =
          Enum.flat_map(labels, fn
            {:d, list} -> list
            _ -> []
          end)

        {:d, mfas}

      # Contains unknown effect (only if no concrete tracked effects above)
      :unknown in labels ->
        :u

      # Has old-style side effects (shouldn't happen with new code, but kept for compatibility)
      has_side_effects?(labels) ->
        :s

      # Lambda-dependent (effects depend on lambda arguments)
      :lambda in labels ->
        :l

      # Context-dependent (reads from execution environment)
      :dependent in labels ->
        :d

      # Only specific exception types - return them
      Enum.all?(labels, &(match?({:e, _}, &1) or &1 == :exn)) and Enum.any?(labels, &(match?({:e, _}, &1))) ->
        # Combine all exception types from {:e, types} tuples
        exception_types =
          labels
          |> Enum.flat_map(fn
            {:e, types} when is_list(types) -> types
            :exn -> [:exn]
            _ -> []
          end)
          |> Enum.uniq()
        {:e, exception_types}

      # Only generic exceptions - return exception types
      Enum.all?(labels, &(&1 == :exn)) ->
        {:e, [:exn]}

      # Mixed exceptions with other effects (including specific exceptions)
      (:exn in labels) or (Enum.any?(labels, &(match?({:e, _}, &1)))) ->
        :s

      # Shouldn't reach here, but default to side effects
      true ->
        :s
    end
  end

  # Check if labels contain side effects with specific MFAs
  defp has_side_effect_mfas?(labels) do
    Enum.any?(labels, fn
      {:s, _list} -> true
      _ -> false
    end)
  end

  # Check if labels contain dependent effects with specific MFAs
  defp has_dependent_effect_mfas?(labels) do
    Enum.any?(labels, fn
      {:d, _list} -> true
      _ -> false
    end)
  end

  # Check if labels contain any old-style side-effecting operations (for compatibility)
  defp has_side_effects?(labels) do
    side_effect_labels = [:io, :file, :process, :network, :state, :ets, :time, :random]
    Enum.any?(labels, fn label -> label in side_effect_labels end)
  end

  @doc """
  Extracts all effect labels from an effect type.

  Returns a list of effect labels in the order they appear in the effect row.
  Side effects are returned as {:s, [MFA list]} tuples.
  Dependent effects are returned as {:d, [MFA list]} tuples.
  """
  def extract_effect_labels(effect) do
    case effect do
      {:effect_empty} ->
        []

      {:effect_label, label} ->
        [label]

      {:s, _list} = side_effect ->
        # Side effects with specific MFAs
        [side_effect]

      {:d, _list} = dependent_effect ->
        # Dependent effects with specific MFAs
        [dependent_effect]

      {:e, _types} = exception_effect ->
        # Exception effects with specific exception types
        [exception_effect]

      {:effect_row, label, tail} ->
        [label | extract_effect_labels(tail)]

      {:effect_var, _name} ->
        # Effect variable - treat as unknown
        [:unknown]

      {:effect_unknown} ->
        [:unknown]

      _ ->
        [:unknown]
    end
  end
end
