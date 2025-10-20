defmodule Litmus.Types.Effects.Layers do
  @moduledoc """
  Effect layer precedence and combining logic.

  This module defines the hierarchy of effect types and provides utilities
  for combining multiple effects into a single, most-impure effect.

  ## Effect Precedence (most impure to least impure)

  1. `:s` - Side effects (I/O, file, process, network, state mutations)
  2. `:d` - Dependent (reads from execution environment)
  3. `:l` - Lambda (effects depend on passed functions)
  4. `:exn` / `{:e, types}` - Exceptions
  5. `:n` - NIF (native code)
  6. `:u` - Unknown
  7. `:p` - Pure (no effects)

  When combining effects, we always take the most impure effect.
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
      7

      iex> Litmus.Types.Effects.Layers.precedence(:p)
      1

      iex> Litmus.Types.Effects.Layers.precedence(:exn)
      4
  """
  @spec precedence(effect_type()) :: integer()
  # Side effects - most impure
  def precedence(:s), do: 7
  # Dependent
  def precedence(:d), do: 6
  # Lambda
  def precedence(:l), do: 5
  # Exception
  def precedence(:exn), do: 4
  # Exception with types
  def precedence({:e, _}), do: 4
  # NIF
  def precedence(:n), do: 3
  # Unknown
  def precedence(:u), do: 2
  # Pure - least impure
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
