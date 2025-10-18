defmodule Litmus.Types.Effects do
  @moduledoc """
  Effect type operations and utilities.

  Implements row-polymorphic effect handling with support for duplicate labels,
  enabling proper treatment of nested effect contexts (e.g., nested exception handlers).
  """


  @doc """
  Combines two effects into a single effect row.

  Handles duplicate labels correctly for nested contexts.

  ## Examples

      iex> combine_effects({:effect_label, :io}, {:effect_label, :exn})
      {:effect_row, :io, {:effect_label, :exn}}

      iex> combine_effects({:effect_empty}, {:effect_label, :io})
      {:effect_label, :io}
  """
  def combine_effects({:effect_empty}, effect2), do: effect2
  def combine_effects(effect1, {:effect_empty}), do: effect1

  def combine_effects({:effect_label, l1}, {:effect_label, l2}) do
    {:effect_row, l1, {:effect_label, l2}}
  end

  def combine_effects({:effect_label, l}, effect) do
    {:effect_row, l, effect}
  end

  def combine_effects({:effect_row, l, tail}, effect) do
    {:effect_row, l, combine_effects(tail, effect)}
  end

  def combine_effects(effect1, effect2) do
    # For variables and unknowns, create a row
    {:effect_row, extract_label(effect1), effect2}
  end

  @doc """
  Removes an effect label from an effect row.

  This is used when handling effects (e.g., catch removes exn).
  Returns the modified effect and whether the label was found.

  ## Examples

      iex> remove_effect(:exn, {:effect_row, :exn, {:effect_label, :io}})
      {{:effect_label, :io}, true}

      iex> remove_effect(:exn, {:effect_row, :exn, {:effect_row, :exn, {:effect_empty}}})
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

      iex> has_effect?(:io, {:effect_row, :io, {:effect_label, :exn}})
      true

      iex> has_effect?(:state, {:effect_label, :io})
      false
  """
  def has_effect?(_label, {:effect_empty}), do: false
  def has_effect?(label, {:effect_label, l}), do: label == l
  def has_effect?(label, {:effect_row, l, tail}) do
    label == l or has_effect?(label, tail)
  end
  def has_effect?(_label, _), do: :unknown  # For variables and unknowns

  @doc """
  Checks if an effect is pure (empty).

  ## Examples

      iex> is_pure?({:effect_empty})
      true

      iex> is_pure?({:effect_label, :io})
      false
  """
  def is_pure?({:effect_empty}), do: true
  def is_pure?(_), do: false

  @doc """
  Flattens nested effect rows for normalization.

  Preserves duplicate labels but flattens the structure.

  ## Examples

      iex> flatten_effect({:effect_row, :io, {:effect_row, :exn, {:effect_empty}}})
      {:effect_row, :io, {:effect_row, :exn, {:effect_empty}}}
  """
  def flatten_effect({:effect_empty} = e), do: e
  def flatten_effect({:effect_label, _} = e), do: e
  def flatten_effect({:effect_var, _} = e), do: e
  def flatten_effect({:effect_unknown} = e), do: e

  def flatten_effect({:effect_row, label, tail}) do
    {:effect_row, label, flatten_effect(tail)}
  end

  @doc """
  Converts a list of effect labels into an effect row.

  ## Examples

      iex> from_list([:io, :exn, :state])
      {:effect_row, :io, {:effect_row, :exn, {:effect_label, :state}}}

      iex> from_list([])
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

  ## Examples

      iex> to_list({:effect_row, :io, {:effect_label, :exn}})
      [:io, :exn]

      iex> to_list({:effect_var, :e})
      :unknown
  """
  def to_list({:effect_empty}), do: []
  def to_list({:effect_label, label}), do: [label]
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
  """
  def from_mfa({module, function, arity} = mfa) do
    effect_type = Litmus.Effects.Registry.effect_type(mfa)

    case effect_type do
      # Pure function - no effects
      :p -> {:effect_empty}

      # Exception - can raise
      :exn -> {:effect_label, :exn}

      # Side effects - map to generic state effect since we don't distinguish fine-grained categories
      :s -> determine_specific_effect(module, function, arity)

      # NIF - native implemented function
      :n -> {:effect_label, :nif}

      # Unknown or not in registry
      _ -> {:effect_unknown}
    end
  end

  # Helper to determine specific effect type from module/function
  # This provides fine-grained effects for better analysis
  defp determine_specific_effect(module, function, _arity) do
    case {module, function} do
      # Kernel process operations
      {Kernel, fun} when fun in [:send, :spawn, :spawn_link, :spawn_monitor, :apply] ->
        {:effect_label, :process}

      # Module-based categorization
      {File, _} -> {:effect_label, :file}
      {IO, _} -> {:effect_label, :io}
      {Logger, _} -> {:effect_label, :io}
      {Process, _} -> {:effect_label, :process}
      {Port, _} -> {:effect_label, :process}
      {Agent, _} -> {:effect_label, :process}
      {Task, _} -> {:effect_label, :process}
      {GenServer, _} -> {:effect_label, :process}
      {Supervisor, _} -> {:effect_label, :process}
      {System, _} -> {:effect_label, :state}
      {Application, _} -> {:effect_label, :state}
      {Code, _} -> {:effect_label, :state}

      # Erlang modules
      {mod, _} when mod in [:gen_tcp, :gen_udp, :inet, :ssl] ->
        {:effect_label, :network}

      {mod, _} when mod in [:ets, :dets] ->
        {:effect_label, :ets}

      {mod, _} when mod in [:rand, :random] ->
        {:effect_label, :random}

      {mod, _} when mod == :os or mod == :erlang ->
        {:effect_label, :state}

      # Default: generic state effect
      _ -> {:effect_label, :state}
    end
  end

  @doc """
  Determines if an effect is a subeffect of another.

  Used for effect polymorphism and checking.
  """
  def subeffect?({:effect_empty}, _), do: true
  def subeffect?(_, {:effect_empty}), do: false
  def subeffect?({:effect_label, l1}, {:effect_label, l2}), do: l1 == l2
  def subeffect?({:effect_label, l}, {:effect_row, l2, tail}) do
    l == l2 or subeffect?({:effect_label, l}, tail)
  end
  def subeffect?({:effect_row, l, t1}, effect2) do
    has_effect?(l, effect2) and subeffect?(t1, remove_first(l, effect2))
  end
  def subeffect?(_, {:effect_unknown}), do: true  # Unknown accepts everything
  def subeffect?({:effect_unknown}, _), do: false  # But isn't a subeffect of specific effects
  def subeffect?(_, _), do: :unknown  # Can't determine for variables

  # Helper to extract a label from an effect (for error messages)
  defp extract_label({:effect_label, l}), do: l
  defp extract_label({:effect_row, l, _}), do: l
  defp extract_label(_), do: :unknown

  # Helper to remove first occurrence of a label
  defp remove_first(label, effect) do
    {result, _found} = remove_effect(label, effect)
    result
  end
end