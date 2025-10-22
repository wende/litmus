defmodule Litmus.Types.Effects do
  @moduledoc """
  Effect type operations and utilities.

  Implements row-polymorphic effect handling with support for duplicate labels,
  enabling proper treatment of nested effect contexts (e.g., nested exception handlers).
  """

  @doc """
  Combines two effects into a single effect row.

  Handles duplicate labels correctly for nested contexts.
  Side effects and dependent effects are merged into single {:s, list} and {:d, list} when possible.

  ## Examples

      iex> alias Litmus.Types.Effects
      iex> Effects.combine_effects({:effect_label, :exn}, {:effect_label, :lambda})
      {:effect_row, :exn, {:effect_label, :lambda}}

      iex> alias Litmus.Types.Effects
      iex> Effects.combine_effects({:effect_empty}, {:effect_label, :exn})
      {:effect_label, :exn}

      iex> alias Litmus.Types.Effects
      iex> Effects.combine_effects({:s, ["File.read/1"]}, {:s, ["IO.puts/1"]})
      {:s, ["File.read/1", "IO.puts/1"]}

      iex> alias Litmus.Types.Effects
      iex> Effects.combine_effects({:d, ["System.get_env/1"]}, {:d, ["Process.get/1"]})
      {:d, ["Process.get/1", "System.get_env/1"]}

      iex> alias Litmus.Types.Effects
      iex> Effects.combine_effects({:e, ["Elixir.ArgumentError"]}, {:e, ["Elixir.KeyError"]})
      {:e, ["Elixir.ArgumentError", "Elixir.KeyError"]}
  """
  def combine_effects({:effect_empty}, effect2), do: effect2
  def combine_effects(effect1, {:effect_empty}), do: effect1

  # Combine two side effect lists (deduplicated)
  def combine_effects({:s, list1}, {:s, list2}) do
    {:s, (list1 ++ list2) |> Enum.uniq() |> Enum.sort()}
  end

  # Combine two dependent effect lists (deduplicated)
  def combine_effects({:d, list1}, {:d, list2}) do
    {:d, (list1 ++ list2) |> Enum.uniq() |> Enum.sort()}
  end

  # Combine two exception effect lists (deduplicated and sorted)
  def combine_effects({:e, list1}, {:e, list2}) do
    {:e, (list1 ++ list2) |> Enum.uniq() |> Enum.sort()}
  end

  # Combine side effect with other effects
  def combine_effects({:s, _list} = s, effect) do
    {:effect_row, s, effect}
  end

  def combine_effects(effect, {:s, _list} = s) do
    {:effect_row, extract_label(effect), s}
  end

  # Combine dependent effect with other effects
  def combine_effects({:d, _list} = d, effect) do
    {:effect_row, d, effect}
  end

  def combine_effects(effect, {:d, _list} = d) do
    {:effect_row, extract_label(effect), d}
  end

  # Combine exception effect with other effects
  def combine_effects({:e, _list} = e, effect) do
    {:effect_row, e, effect}
  end

  def combine_effects(effect, {:e, _list} = e) do
    {:effect_row, extract_label(effect), e}
  end

  def combine_effects({:effect_label, l1}, {:effect_label, l2}) do
    {:effect_row, l1, {:effect_label, l2}}
  end

  def combine_effects({:effect_label, l}, effect) do
    {:effect_row, l, effect}
  end

  def combine_effects({:effect_row, l, tail}, effect) do
    {:effect_row, l, combine_effects(tail, effect)}
  end

  # Combine two effect variables - keep as separate variables in a row
  def combine_effects({:effect_var, _} = v1, {:effect_var, _} = v2) do
    {:effect_row, v1, v2}
  end

  # Combine effect variable with other effects
  def combine_effects({:effect_var, _} = v, effect) do
    {:effect_row, v, effect}
  end

  def combine_effects(effect, {:effect_var, _} = v) do
    {:effect_row, extract_label(effect), v}
  end

  def combine_effects(effect1, effect2) do
    # For unknowns and other cases, create a row
    {:effect_row, extract_label(effect1), effect2}
  end

  @doc """
  Removes an effect label from an effect row.

  This is used when handling effects (e.g., catch removes exn).
  Returns the modified effect and whether the label was found.

  ## Examples

      iex> alias Litmus.Types.Effects
      iex> Effects.remove_effect(:exn, {:effect_row, :exn, {:effect_label, :io}})
      {{:effect_label, :io}, true}

      iex> alias Litmus.Types.Effects
      iex> Effects.remove_effect(:exn, {:effect_row, :exn, {:effect_row, :exn, {:effect_empty}}})
      {{:effect_row, :exn, {:effect_empty}}, true}  # Removes only first occurrence
  """
  def remove_effect(_label, {:effect_empty}) do
    {{:effect_empty}, false}
  end

  def remove_effect(label, {:effect_label, l}) when label == l do
    {{:effect_empty}, true}
  end

  def remove_effect(_label, {:effect_label, l}) do
    {{:effect_label, l}, false}
  end

  def remove_effect(label, {:effect_row, l, tail}) when label == l do
    # Found the label, remove it (only first occurrence for nested handlers)
    {tail, true}
  end

  def remove_effect(label, {:effect_row, l, tail}) do
    # Not this label, continue searching
    {new_tail, found} = remove_effect(label, tail)

    if found do
      {{:effect_row, l, new_tail}, true}
    else
      {{:effect_row, l, tail}, false}
    end
  end

  def remove_effect(_label, effect) do
    # Variables and unknowns remain unchanged
    {effect, false}
  end

  @doc """
  Checks if an effect contains a specific label.

  ## Examples

      iex> alias Litmus.Types.Effects
      iex> Effects.has_effect?(:exn, {:effect_row, :exn, {:effect_label, :lambda}})
      true

      iex> alias Litmus.Types.Effects
      iex> Effects.has_effect?(:exn, {:effect_label, :lambda})
      false
  """
  def has_effect?(_label, {:effect_empty}), do: false
  def has_effect?(label, {:effect_label, l}), do: label == l
  # Exception effects match exn label
  def has_effect?(:exn, {:e, _types}), do: true
  def has_effect?(_label, {:e, _types}), do: false
  # Side effects don't match label queries
  def has_effect?(_label, {:s, _list}), do: false
  # Dependent effects don't match label queries
  def has_effect?(_label, {:d, _list}), do: false

  def has_effect?(label, {:effect_row, l, tail}) do
    label == l or has_effect?(label, tail)
  end

  # For variables and unknowns
  def has_effect?(_label, _), do: :unknown

  @doc """
  Checks if an effect is pure (empty).

  ## Examples

      iex> alias Litmus.Types.Effects
      iex> Effects.is_pure?({:effect_empty})
      true

      iex> alias Litmus.Types.Effects
      iex> Effects.is_pure?({:effect_label, :io})
      false
  """
  def is_pure?({:effect_empty}), do: true
  def is_pure?(_), do: false

  @doc """
  Flattens nested effect rows for normalization.

  Preserves duplicate labels but flattens the structure.

  ## Examples

      iex> alias Litmus.Types.Effects
      iex> Effects.flatten_effect({:effect_row, :exn, {:effect_row, :lambda, {:effect_empty}}})
      {:effect_row, :exn, {:effect_row, :lambda, {:effect_empty}}}
  """
  def flatten_effect({:effect_empty} = e), do: e
  def flatten_effect({:effect_label, _} = e), do: e
  def flatten_effect({:effect_var, _} = e), do: e
  def flatten_effect({:effect_unknown} = e), do: e
  # Side effect lists are already flat
  def flatten_effect({:s, _list} = e), do: e
  # Dependent effect lists are already flat
  def flatten_effect({:d, _list} = e), do: e

  def flatten_effect({:effect_row, label, tail}) do
    {:effect_row, label, flatten_effect(tail)}
  end

  @doc """
  Converts a list of effect labels into an effect row.

  ## Examples

      iex> alias Litmus.Types.Effects
      iex> Effects.from_list([:io, :exn, :state])
      {:effect_row, :io, {:effect_row, :exn, {:effect_label, :state}}}

      iex> alias Litmus.Types.Effects
      iex> Effects.from_list([])
      {:effect_empty}
  """
  def from_list([]), do: {:effect_empty}
  def from_list([label]), do: {:effect_label, label}

  def from_list([label | rest]) do
    {:effect_row, label, from_list(rest)}
  end

  @doc """
  Converts an effect row to a list of labels.

  Returns :unknown for variables or unknown effects.
  Side effects and dependent effects are returned as {:s, mfa_list} and {:d, mfa_list}.

  ## Examples

      iex> alias Litmus.Types.Effects
      iex> Effects.to_list({:effect_row, :exn, {:effect_label, :lambda}})
      [:exn, :lambda]

      iex> alias Litmus.Types.Effects
      iex> Effects.to_list({:effect_var, :e})
      :unknown

      iex> alias Litmus.Types.Effects
      iex> Effects.to_list({:s, ["File.read/1", "IO.puts/1"]})
      [{:s, ["File.read/1", "IO.puts/1"]}]

      iex> alias Litmus.Types.Effects
      iex> Effects.to_list({:d, ["System.get_env/1"]})
      [{:d, ["System.get_env/1"]}]
  """
  def to_list({:effect_empty}), do: []
  def to_list({:effect_label, label}), do: [label]
  # Return side effects as a single element
  def to_list({:s, _list} = s), do: [s]
  # Return dependent effects as a single element
  def to_list({:d, _list} = d), do: [d]

  def to_list({:effect_row, label, tail}) do
    case to_list(tail) do
      :unknown -> :unknown
      list -> [label | list]
    end
  end

  def to_list(_), do: :unknown

  @doc """
  Simplifies an effect by removing redundant structure.

  Does NOT remove duplicate labels (they're semantically meaningful).
  """
  def simplify({:effect_row, label, {:effect_empty}}) do
    {:effect_label, label}
  end

  def simplify(effect), do: effect

  @doc """
  Creates an effect from an MFA based on the effect registry.

  Maps from compact PURITY effect types to the internal effect representation.
  Side effects and dependent effects are now tracked with specific function names.

  If the MFA has a resolution mapping to leaf BIFs, those leaf BIFs are used instead.
  """
  def from_mfa({_module, _function, _arity} = mfa) do
    # First, check if this MFA has a direct effect type in the registry
    direct_effect = Litmus.Effects.Registry.effect_type(mfa)

    # If it has a direct effect, use that instead of resolving
    # (Resolution is only for understanding implementation details, not for effect determination)
    if direct_effect != nil do
      # Has direct effect - use it (single effect)
      build_single_effect(mfa, direct_effect)
    else
      # No direct effect - try resolution as fallback
      case Litmus.Effects.Registry.resolve_to_leaves(mfa) do
        {:ok, leaves} ->
          # This is a wrapper function - resolve to leaves
          # Get effects from all leaves and combine using most severe
          leaf_effects = Enum.map(leaves, &Litmus.Effects.Registry.effect_type/1)
          leaf_effect = Litmus.Types.Effects.Layers.combine_all(leaf_effects)

          # Filter out non-effectful leaves - we only want to track concrete side effects
          # Exclude: pure (:p), lambda-dependent (:l), unknown (:u), nif (:n)
          # Include: side effects (:s), dependent (:d), exceptions (:e/:exn)
          effectful_leaves =
            Enum.filter(leaves, fn leaf ->
              leaf_effect_type = Litmus.Effects.Registry.effect_type(leaf)
              leaf_effect_type not in [:p, :l, :u, :n]
            end)

          build_single_effect_with_leaves({mfa, effectful_leaves}, leaf_effect)

        :not_found ->
          # No resolution and no direct effect - unknown
          {:effect_unknown}
      end
    end
  end

  # Helper to build single effect but track actual leaves
  defp build_single_effect_with_leaves({_orig_mfa, leaves}, effect_type) do
    case effect_type do
      # Pure function - no effects
      :p -> {:effect_empty}
      # Dependent - reads from execution environment, track specific function(s)
      :d -> {:d, Enum.map(leaves, &format_mfa_tuple/1)}
      # Dependent - tuple format from runtime cache (already has function names)
      {:d, list} when is_list(list) -> {:d, list}
      # Lambda - effects depend on passed lambdas
      :l -> {:effect_label, :lambda}
      # Exception - can raise (atom format from JSON)
      :exn -> {:effect_label, :exn}
      # Exception - can raise (simple :e atom from registry)
      :e -> {:effect_label, :exn}
      # Exception - can raise (tuple format from runtime cache with specific exception types)
      {:e, types} -> {:e, types}
      # Side effects - track specific function MFA(s) - use leaves for wrapper functions
      :s -> {:s, Enum.map(leaves, &format_mfa_tuple/1)}
      # Side effects - tuple format from runtime cache (already has function names)
      {:s, list} when is_list(list) -> {:s, list}
      # NIF - native implemented function
      :n -> {:effect_label, :nif}
      # Unknown (atom) or not in registry
      :u -> {:effect_unknown}
      # Unknown or not in registry
      _ -> {:effect_unknown}
    end
  end

  # Helper to build a single effect from an MFA and effect type
  defp build_single_effect(mfa, effect_type) do
    case effect_type do
      # Pure function - no effects
      :p -> {:effect_empty}
      # Dependent - reads from execution environment, track specific function(s)
      :d -> {:d, [format_mfa_tuple(mfa)]}
      # Dependent - tuple format from runtime cache (already has function names)
      {:d, list} when is_list(list) -> {:d, list}
      # Lambda - effects depend on passed lambdas
      :l -> {:effect_label, :lambda}
      # Exception - can raise (atom format from JSON)
      :exn -> {:effect_label, :exn}
      # Exception - can raise (simple :e atom from registry)
      :e -> {:effect_label, :exn}
      # Exception - can raise (tuple format from runtime cache with specific exception types)
      {:e, types} -> {:e, types}
      # Side effects - track specific function MFA(s)
      :s -> {:s, [format_mfa_tuple(mfa)]}
      # Side effects - tuple format from runtime cache (already has function names)
      {:s, list} when is_list(list) -> {:s, list}
      # NIF - native implemented function
      :n -> {:effect_label, :nif}
      # Unknown (atom) or not in registry
      :u -> {:effect_unknown}
      # Unknown or not in registry
      _ -> {:effect_unknown}
    end
  end

  # Helper to format MFA tuple as a string
  defp format_mfa_tuple({m, f, a}), do: format_mfa(m, f, a)

  # Helper to format an MFA as a string
  defp format_mfa(module, function, arity) do
    # For Elixir modules, use the short name (e.g., File instead of Elixir.File)
    module_str =
      case module do
        mod when is_atom(mod) ->
          mod_str = Atom.to_string(mod)

          case mod_str do
            "Elixir." <> rest -> rest
            _ -> mod_str
          end

        _ ->
          inspect(module)
      end

    "#{module_str}.#{function}/#{arity}"
  end

  @doc """
  Determines if an effect is a subeffect of another.

  Used for effect polymorphism and checking.
  """
  def subeffect?({:effect_empty}, _), do: true
  def subeffect?(_, {:effect_empty}), do: false
  def subeffect?({:effect_label, l1}, {:effect_label, l2}), do: l1 == l2

  def subeffect?({:s, list1}, {:s, list2}) do
    # All effects in list1 must be in list2
    Enum.all?(list1, &(&1 in list2))
  end

  def subeffect?({:d, list1}, {:d, list2}) do
    # All effects in list1 must be in list2
    Enum.all?(list1, &(&1 in list2))
  end

  def subeffect?({:effect_label, l}, {:effect_row, l2, tail}) do
    l == l2 or subeffect?({:effect_label, l}, tail)
  end

  def subeffect?({:effect_row, l, t1}, effect2) do
    has_effect?(l, effect2) and subeffect?(t1, remove_first(l, effect2))
  end

  # Unknown accepts everything
  def subeffect?(_, {:effect_unknown}), do: true
  # But isn't a subeffect of specific effects
  def subeffect?({:effect_unknown}, _), do: false
  # Can't determine for variables
  def subeffect?(_, _), do: :unknown

  @doc """
  Extracts all exception types from an effect.

  Returns a list of exception module names or :dynamic/:exn markers.

  ## Examples

      iex> alias Litmus.Types.Effects
      iex> Effects.extract_exception_types({:e, ["Elixir.ArgumentError", "Elixir.KeyError"]})
      ["Elixir.ArgumentError", "Elixir.KeyError"]

      iex> alias Litmus.Types.Effects
      iex> Effects.extract_exception_types({:effect_label, :exn})
      [:exn]

      iex> alias Litmus.Types.Effects
      iex> Effects.extract_exception_types({:effect_row, {:e, ["Elixir.ArgumentError"]}, {:effect_label, :io}})
      ["Elixir.ArgumentError"]
  """
  def extract_exception_types({:e, types}) when is_list(types), do: types
  def extract_exception_types({:effect_label, :exn}), do: [:exn]

  def extract_exception_types({:effect_row, {:e, types}, tail}) when is_list(types) do
    types ++ extract_exception_types(tail)
  end

  def extract_exception_types({:effect_row, :exn, tail}) do
    [:exn | extract_exception_types(tail)]
  end

  def extract_exception_types({:effect_row, _, tail}) do
    extract_exception_types(tail)
  end

  def extract_exception_types(_), do: []

  @doc """
  Extracts the return effect from a closure type.

  When a function returns a closure, this extracts the effect the closure
  will have when called (as opposed to the effect of creating/capturing it).

  ## Examples

      iex> alias Litmus.Types.Effects
      iex> alias Litmus.Types.Core
      iex> closure_type = Core.closure_type(:int, Core.empty_effect(), Core.single_effect(:io))
      iex> Effects.extract_closure_return_effect(closure_type)
      {:effect_label, :io}
  """
  def extract_closure_return_effect({:closure, _arg_type, _captured_effect, return_effect}) do
    return_effect
  end

  def extract_closure_return_effect(_type) do
    # Not a closure type, return empty effect
    {:effect_empty}
  end

  # Helper to extract a label from an effect (for error messages)
  defp extract_label({:effect_label, l}), do: l
  defp extract_label({:effect_row, l, _}), do: l
  # Return the whole side effect for rows
  defp extract_label({:s, list}), do: {:s, list}
  # Return the whole dependent effect for rows
  defp extract_label({:d, list}), do: {:d, list}
  # Return the whole exception effect for rows
  defp extract_label({:e, list}), do: {:e, list}
  defp extract_label(_), do: :unknown

  # Helper to remove first occurrence of a label
  defp remove_first(label, effect) do
    {result, _found} = remove_effect(label, effect)
    result
  end
end
