defmodule Litmus.Types.Effects.Layers do
  @moduledoc """
  Effect layer precedence and combining logic.

  This module defines the hierarchy of effect types and provides utilities
  for combining multiple effects into a single, most-severe effect.

  ## Effect Precedence (most severe to least severe)

  1. `:u` - Unknown (cannot analyze, assume worst case)
  2. `:n` - NIF (native code, black box)
  3. `:s` - Side effects (I/O, file, process, network, state mutations)
  4. `:d` - Dependent (reads from execution environment)
  5. `:exn` / `{:e, types}` - Exceptions (will definitely raise)
  6. `:l` - Lambda (only impure if passed impure function)
  7. `:p` - Pure (no effects)

  When combining effects, we always take the most severe effect (highest precedence).
  This ensures conservative analysis for safety.

  Note: Lambda has lower precedence than exceptions because if we determine a function
  is lambda-dependent, it means everything we analyzed was pure - the function is only
  as impure as what you pass to it. In contrast, exceptions will definitely raise.
  """

  @type effect_type ::
          :p
          | :s
          | :d
          | :l
          | :n
          | :u
          | :exn
          | {:e, list()}

  @doc """
  Returns the precedence level of an effect type.

  Higher numbers indicate more impure/restrictive effects.

  ## Examples

      iex> Litmus.Types.Effects.Layers.precedence(:s)
      5

      iex> Litmus.Types.Effects.Layers.precedence(:p)
      1

      iex> Litmus.Types.Effects.Layers.precedence(:exn)
      3
  """
  @spec precedence(effect_type()) :: integer()
  # Unknown - most severe (cannot analyze, assume worst)
  def precedence(:u), do: 7
  # NIF - native code, black box
  def precedence(:n), do: 6
  # Side effects - performs I/O, mutates state
  def precedence(:s), do: 5
  # Dependent - reads from execution environment
  def precedence(:d), do: 4
  # Exception - will definitely raise
  def precedence(:exn), do: 3
  # Exception with types
  def precedence({:e, _}), do: 3
  # Lambda - only impure if passed impure function
  def precedence(:l), do: 2
  # Pure - least severe
  def precedence(:p), do: 1
  # Nil has lowest precedence
  def precedence(nil), do: 0

  @doc """
  Combines two effect types, returning the most impure one.

  ## Examples

      iex> Litmus.Types.Effects.Layers.combine(:p, :s)
      :s

      iex> Litmus.Types.Effects.Layers.combine(:l, :d)
      :d

      iex> Litmus.Types.Effects.Layers.combine(:p, :p)
      :p

      iex> Litmus.Types.Effects.Layers.combine(:exn, {:e, [:error]})
      :exn
  """
  @spec combine(effect_type() | nil, effect_type() | nil) :: effect_type()
  def combine(e1, e2) do
    if precedence(e1) >= precedence(e2) do
      e1
    else
      e2
    end
  end

  @doc """
  Combines a list of effect types into a single, most impure effect.

  Filters out nil values and returns the effect with highest precedence.

  ## Examples

      iex> Litmus.Types.Effects.Layers.combine_all([:p, :s, :l])
      :s

      iex> Litmus.Types.Effects.Layers.combine_all([:p, :p, :p])
      :p

      iex> Litmus.Types.Effects.Layers.combine_all([nil, :s, nil, :l])
      :s

      iex> Litmus.Types.Effects.Layers.combine_all([])
      :p
  """
  @spec combine_all([effect_type() | nil]) :: effect_type()
  def combine_all([]), do: :p

  def combine_all(effects) do
    effects
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&precedence/1, fn -> :p end)
  end

  @doc """
  Checks if an effect type is pure.

  ## Examples

      iex> Litmus.Types.Effects.Layers.pure?(:p)
      true

      iex> Litmus.Types.Effects.Layers.pure?(:s)
      false
  """
  @spec pure?(effect_type()) :: boolean()
  def pure?(:p), do: true
  def pure?(_), do: false

  @doc """
  Checks if an effect type represents side effects.

  ## Examples

      iex> Litmus.Types.Effects.Layers.has_side_effects?(:s)
      true

      iex> Litmus.Types.Effects.Layers.has_side_effects?(:p)
      false
  """
  @spec has_side_effects?(effect_type()) :: boolean()
  def has_side_effects?(:s), do: true
  def has_side_effects?(_), do: false

  @doc """
  Checks if an effect type is dependent on execution environment.

  ## Examples

      iex> Litmus.Types.Effects.Layers.dependent?(:d)
      true

      iex> Litmus.Types.Effects.Layers.dependent?(:s)
      false
  """
  @spec dependent?(effect_type()) :: boolean()
  def dependent?(:d), do: true
  def dependent?(_), do: false

  @doc """
  Checks if an effect type is lambda-dependent.

  ## Examples

      iex> Litmus.Types.Effects.Layers.lambda_dependent?(:l)
      true

      iex> Litmus.Types.Effects.Layers.lambda_dependent?(:p)
      false
  """
  @spec lambda_dependent?(effect_type()) :: boolean()
  def lambda_dependent?(:l), do: true
  def lambda_dependent?(_), do: false

  @doc """
  Returns a human-readable description of an effect type.

  ## Examples

      iex> Litmus.Types.Effects.Layers.describe(:s)
      "side effects"

      iex> Litmus.Types.Effects.Layers.describe(:p)
      "pure"

      iex> Litmus.Types.Effects.Layers.describe({:e, [:error]})
      "exception"
  """
  @spec describe(effect_type()) :: String.t()
  def describe(:p), do: "pure"
  def describe(:s), do: "side effects"
  def describe(:d), do: "dependent on environment"
  def describe(:l), do: "lambda-dependent"
  def describe(:exn), do: "exception"
  def describe({:e, _}), do: "exception"
  def describe(:n), do: "native code (NIF)"
  def describe(:u), do: "unknown"
  def describe(nil), do: "none"
end
