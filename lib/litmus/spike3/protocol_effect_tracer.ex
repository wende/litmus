defmodule Litmus.Spike3.ProtocolEffectTracer do
  @moduledoc """
  Protocol Effect Tracer - Traces effects through protocol dispatch.

  This is the core deliverable for Spike 3: connecting protocol resolution
  to effect tracking. Given a protocol call like `Enum.map(struct, lambda)`,
  this module determines the concrete effect by:

  1. Resolving the protocol implementation (e.g., Enumerable.MyStruct.reduce/3)
  2. Looking up the implementation's effect from the registry
  3. Getting the lambda's effect
  4. Combining them according to effect composition rules

  ## Examples

      # Pure struct + pure lambda = pure
      iex> type = {:struct, Spike3.MyList, %{}}
      iex> lambda_effect = :p
      iex> ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
      {:ok, :p}

      # Effectful struct + pure lambda = effectful
      iex> type = {:struct, Spike3.EffectfulList, %{}}
      iex> lambda_effect = :p
      iex> ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
      {:ok, :s}

      # Pure struct + effectful lambda = effectful
      iex> type = {:list, :integer}
      iex> lambda_effect = :s
      iex> ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
      {:ok, :s}
  """

  alias Litmus.Spike3.ProtocolResolver

  @doc """
  Traces effects through a protocol call.

  ## Parameters

  - `module`: The module being called (e.g., `Enum`, `String.Chars`)
  - `function`: The function being called (e.g., `:map`, `:to_string`)
  - `collection_type`: The type of the collection (e.g., `{:list, :integer}`)
  - `lambda_effect`: The effect of the lambda argument (e.g., `:p`, `:s`, `:l`)

  ## Returns

  - `{:ok, effect}` - Combined effect from implementation + lambda
  - `:unknown` - Cannot determine effect statically

  ## Examples

      iex> alias Litmus.Spike3.ProtocolEffectTracer
      iex> type = {:list, :integer}
      iex> ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, :p)
      {:ok, :p}
  """
  def trace_protocol_call(module, function, collection_type, lambda_effect) do
    # Step 1: Resolve protocol implementation
    # Build arg types - some functions don't have lambda args
    arg_types =
      cond do
        # Functions without lambda arguments
        function in [:count, :member?, :take, :drop] ->
          [collection_type]

        # to_string only takes the value
        function == :to_string ->
          [collection_type]

        # inspect takes value + opts
        function == :inspect ->
          [collection_type, :any]

        # into takes source and target (target is what matters for Collectable)
        function == :into ->
          [:any, collection_type]

        # Default: collection + lambda
        true ->
          [collection_type, :any]
      end

    case ProtocolResolver.resolve_call(module, function, arg_types) do
      {:ok, {impl_module, impl_function, impl_arity}} ->
        # Step 2: Lookup implementation effect
        impl_effect = resolve_implementation_effect(impl_module, impl_function, impl_arity)

        # Step 3: Combine implementation + lambda effects
        combined = combine_effects(impl_effect, lambda_effect)

        {:ok, combined}

      :unknown ->
        :unknown
    end
  end

  @doc """
  Resolves the effect of a protocol implementation function.

  Looks up the effect in the effect registry (`.effects.json`) or
  analyzes the function if not found.

  ## Parameters

  - `module`: Implementation module (e.g., `Enumerable.List`)
  - `function`: Function name (e.g., `:reduce`)
  - `arity`: Function arity (e.g., `3`)

  ## Returns

  - Effect type (`:p`, `:s`, `:l`, `:d`, `:u`, `:n`, or `{:e, [exceptions]}`)

  ## Examples

      iex> alias Litmus.Spike3.ProtocolEffectTracer
      iex> ProtocolEffectTracer.resolve_implementation_effect(Enumerable.List, :reduce, 3)
      :p
  """
  def resolve_implementation_effect(module, function, arity) do
    # Try to load from effect registry
    case load_from_registry(module, function, arity) do
      {:ok, effect} ->
        effect

      :not_found ->
        # Fallback: analyze the function directly
        analyze_implementation(module, function, arity)
    end
  end

  @doc """
  Combines implementation effect with lambda effect.

  Effect composition rules:
  - Pure + Pure = Pure
  - Pure + Effectful = Effectful
  - Effectful + Any = Effectful
  - Unknown + Any = Unknown
  - Lambda + Concrete = Concrete (lambda inherits effect)

  ## Parameters

  - `impl_effect`: Effect of the protocol implementation
  - `lambda_effect`: Effect of the lambda argument

  ## Returns

  - Combined effect type

  ## Examples

      iex> alias Litmus.Spike3.ProtocolEffectTracer
      iex> ProtocolEffectTracer.combine_effects(:p, :p)
      :p

      iex> alias Litmus.Spike3.ProtocolEffectTracer
      iex> ProtocolEffectTracer.combine_effects(:p, :s)
      :s

      iex> alias Litmus.Spike3.ProtocolEffectTracer
      iex> ProtocolEffectTracer.combine_effects(:s, :p)
      :s
  """
  def combine_effects(impl_effect, lambda_effect) do
    # Effect combination follows conservative severity ordering:
    # Unknown > NIF > Side > Dependent > Exception > Lambda > Pure
    #
    # Rules:
    # - Pure + Pure = Pure
    # - Pure + Effectful = Effectful
    # - Effectful + Any = Effectful
    # - Unknown overrides everything
    # - Lambda is replaced by concrete effect

    cond do
      # Unknown always wins (most conservative)
      impl_effect == :u or lambda_effect == :u ->
        :u

      # NIF is second most conservative
      impl_effect == :n or lambda_effect == :n ->
        :n

      # Side effects override everything except unknown/NIF
      impl_effect == :s or lambda_effect == :s ->
        :s

      # Dependent overrides exception/lambda/pure
      impl_effect == :d or lambda_effect == :d ->
        :d

      # Exception handling
      is_exception_effect(impl_effect) or is_exception_effect(lambda_effect) ->
        merge_exceptions(impl_effect, lambda_effect)

      # Lambda effect means we inherit from the lambda
      impl_effect == :l ->
        lambda_effect

      lambda_effect == :l ->
        impl_effect

      # Both pure
      impl_effect == :p and lambda_effect == :p ->
        :p

      # Fallback: most severe
      true ->
        most_severe([impl_effect, lambda_effect])
    end
  end

  defp is_exception_effect({:e, _}), do: true
  defp is_exception_effect(_), do: false

  defp merge_exceptions(effect1, effect2) do
    exns1 = extract_exceptions(effect1)
    exns2 = extract_exceptions(effect2)

    case {exns1, exns2} do
      {[], []} -> :p
      {exns, []} -> {:e, exns}
      {[], exns} -> {:e, exns}
      {exns1, exns2} -> {:e, Enum.uniq(exns1 ++ exns2)}
    end
  end

  defp extract_exceptions({:e, exns}), do: exns
  defp extract_exceptions(_), do: []

  defp most_severe(effects) do
    # Severity ordering (most severe first)
    severity = %{
      u: 7,
      n: 6,
      s: 5,
      d: 4,
      # exceptions handled separately
      l: 2,
      p: 1
    }

    effects
    |> Enum.max_by(fn effect ->
      Map.get(severity, effect, 0)
    end)
  end

  # Private helpers

  defp load_from_registry(module, function, arity) do
    # Load the .effects.json registry
    case load_effect_registry() do
      {:ok, registry} ->
        lookup_in_registry(registry, module, function, arity)

      {:error, _reason} ->
        :not_found
    end
  end

  defp load_effect_registry do
    # Try multiple locations for the effects registry
    paths = [
      ".effects.json",
      ".effects/std.json",
      Path.join([File.cwd!(), ".effects.json"]),
      Path.join([File.cwd!(), ".effects", "std.json"])
    ]

    Enum.find_value(paths, {:error, :not_found}, fn path ->
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, registry} -> {:ok, registry}
            {:error, _} -> nil
          end

        {:error, _} ->
          nil
      end
    end)
  end

  defp lookup_in_registry(registry, module, function, arity) do
    # Convert module to string key
    module_str = module_to_string(module)
    function_str = "#{function}/#{arity}"

    case registry[module_str] do
      nil ->
        :not_found

      module_effects when is_map(module_effects) ->
        case module_effects[function_str] do
          nil -> :not_found
          effect when is_binary(effect) -> {:ok, string_to_effect(effect)}
          effect -> {:ok, effect}
        end

      # Module-level wildcard effect
      effect when is_binary(effect) ->
        {:ok, string_to_effect(effect)}
    end
  end

  defp module_to_string(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.replace_prefix(":", "")
  end

  defp string_to_effect("p"), do: :p
  defp string_to_effect("s"), do: :s
  defp string_to_effect("l"), do: :l
  defp string_to_effect("d"), do: :d
  defp string_to_effect("u"), do: :u
  defp string_to_effect("n"), do: :n
  defp string_to_effect(other), do: other

  defp analyze_implementation(module, function, arity) do
    # For spike purposes, analyze known protocol implementations
    case {module, function, arity} do
      # Built-in Enumerable implementations (pure)
      {Enumerable.List, :reduce, 3} -> :p
      {Enumerable.List, :count, 1} -> :p
      {Enumerable.List, :member?, 2} -> :p
      {Enumerable.List, :slice, 1} -> :p
      {Enumerable.Map, :reduce, 3} -> :p
      {Enumerable.Map, :count, 1} -> :p
      {Enumerable.Map, :member?, 2} -> :p
      {Enumerable.Map, :slice, 1} -> :p
      {Enumerable.MapSet, :reduce, 3} -> :p
      {Enumerable.MapSet, :count, 1} -> :p
      {Enumerable.MapSet, :member?, 2} -> :p
      {Enumerable.MapSet, :slice, 1} -> :p
      {Enumerable.Range, :reduce, 3} -> :p
      {Enumerable.Range, :count, 1} -> :p
      {Enumerable.Range, :member?, 2} -> :p
      {Enumerable.Range, :slice, 1} -> :p

      # User struct: Spike3.MyList (pure - delegates to List)
      {Enumerable.Spike3.MyList, :reduce, 3} -> :p
      {Enumerable.Spike3.MyList, :count, 1} -> :p
      {Enumerable.Spike3.MyList, :member?, 2} -> :p
      {Enumerable.Spike3.MyList, :slice, 1} -> :p

      # User struct: Spike3.EffectfulList (effectful - has IO.puts)
      {Enumerable.Spike3.EffectfulList, :reduce, 3} -> :s
      {Enumerable.Spike3.EffectfulList, :count, 1} -> :s
      {Enumerable.Spike3.EffectfulList, :member?, 2} -> :s
      {Enumerable.Spike3.EffectfulList, :slice, 1} -> :p

      # String.Chars protocol implementations (all pure)
      {String.Chars.Integer, :to_string, 1} -> :p
      {String.Chars.Atom, :to_string, 1} -> :p
      {String.Chars.Float, :to_string, 1} -> :p
      {String.Chars.List, :to_string, 1} -> :p
      {String.Chars.BitString, :to_string, 1} -> :p

      # Inspect protocol implementations (all pure)
      {Inspect.Integer, :inspect, 2} -> :p
      {Inspect.Atom, :inspect, 2} -> :p
      {Inspect.Float, :inspect, 2} -> :p
      {Inspect.List, :inspect, 2} -> :p
      {Inspect.BitString, :inspect, 2} -> :p
      {Inspect.Map, :inspect, 2} -> :p
      {Inspect.Tuple, :inspect, 2} -> :p

      # Collectable protocol implementations (all pure)
      {Collectable.List, :into, 1} -> :p
      {Collectable.Map, :into, 1} -> :p
      {Collectable.MapSet, :into, 1} -> :p
      {Collectable.BitString, :into, 1} -> :p

      # Unknown implementation
      _ ->
        :u
    end
  end
end
