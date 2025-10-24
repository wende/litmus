defmodule Litmus.Spike3.ProtocolResolver do
  @moduledoc """
  Protocol dispatch resolution for static effect analysis.

  Resolves protocol implementations based on type information, enabling
  accurate effect tracking through protocol calls like Enum.map/2.

  ## Examples

      iex> alias Litmus.Spike3.{ProtocolResolver, StructTypes}
      iex> list_type = {:list, :integer}
      iex> ProtocolResolver.resolve_impl(Enumerable, list_type)
      {:ok, Enumerable.List}

      iex> alias Litmus.Spike3.{ProtocolResolver, StructTypes}
      iex> map_type = {:map, []}
      iex> ProtocolResolver.resolve_impl(Enumerable, map_type)
      {:ok, Enumerable.Map}

      iex> alias Litmus.Spike3.{ProtocolResolver, StructTypes}
      iex> struct_type = StructTypes.struct_type(MapSet)
      iex> ProtocolResolver.resolve_impl(Enumerable, struct_type)
      {:ok, Enumerable.MapSet}
  """

  alias Litmus.Spike3.StructTypes

  @doc """
  Resolves a protocol implementation module based on a type.

  Returns {:ok, implementation_module} if the protocol implementation can be determined,
  or :unknown if it cannot be statically resolved.

  ## Parameters
  - protocol: Protocol module (e.g., Enumerable, String.Chars)
  - type: Type descriptor (e.g., {:list, :any}, {:struct, MapSet, %{}})

  ## Examples

      iex> alias Litmus.Spike3.ProtocolResolver
      iex> ProtocolResolver.resolve_impl(Enumerable, {:list, :integer})
      {:ok, Enumerable.List}

      iex> alias Litmus.Spike3.ProtocolResolver
      iex> ProtocolResolver.resolve_impl(Enumerable, :any)
      :unknown
  """
  def resolve_impl(protocol, type) do
    case type do
      # List type -> Enumerable.List, Collectable.List, etc.
      {:list, _elem_type} ->
        resolve_for_builtin(protocol, List)

      # Map type -> Enumerable.Map, Collectable.Map, etc.
      {:map, _} ->
        resolve_for_builtin(protocol, Map)

      # Struct type -> Protocol.StructModule
      {:struct, module, _fields} ->
        resolve_for_struct(protocol, module)

      # Primitive types
      :integer -> resolve_for_builtin(protocol, Integer)
      :float -> resolve_for_builtin(protocol, Float)
      :atom -> resolve_for_builtin(protocol, Atom)
      :string -> resolve_for_builtin(protocol, BitString)
      :binary -> resolve_for_builtin(protocol, BitString)

      # Unknown type
      _ ->
        :unknown
    end
  end

  @doc """
  Gets all known implementations for a protocol.

  Returns a list of implementation modules, handling both consolidated
  and non-consolidated protocols.

  ## Examples

      iex> alias Litmus.Spike3.ProtocolResolver
      iex> impls = ProtocolResolver.get_implementations(Enumerable)
      iex> Enumerable.List in impls
      true

      iex> alias Litmus.Spike3.ProtocolResolver
      iex> impls = ProtocolResolver.get_implementations(String.Chars)
      iex> is_list(impls)
      true
  """
  def get_implementations(protocol) when is_atom(protocol) do
    case Code.ensure_loaded(protocol) do
      {:module, ^protocol} ->
        case protocol.__protocol__(:impls) do
          # Consolidated protocol
          {:consolidated, impl_types} ->
            Enum.map(impl_types, &impl_module(protocol, &1))

          # Non-consolidated protocol
          impl_types when is_list(impl_types) ->
            Enum.map(impl_types, &impl_module(protocol, &1))

          _ ->
            []
        end

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Checks if a protocol has an implementation for a given type.

  ## Examples

      iex> alias Litmus.Spike3.ProtocolResolver
      iex> ProtocolResolver.has_impl?(Enumerable, {:list, :any})
      true

      iex> alias Litmus.Spike3.ProtocolResolver
      iex> ProtocolResolver.has_impl?(Enumerable, :integer)
      false
  """
  def has_impl?(protocol, type) do
    case resolve_impl(protocol, type) do
      {:ok, _impl} -> true
      :unknown -> false
    end
  end

  # Private helpers

  defp resolve_for_builtin(protocol, type_module) do
    impl_module = impl_module(protocol, type_module)

    case Code.ensure_loaded(impl_module) do
      {:module, ^impl_module} -> {:ok, impl_module}
      {:error, _reason} -> :unknown
    end
  end

  defp resolve_for_struct(protocol, struct_module) do
    impl_module = impl_module(protocol, struct_module)

    case Code.ensure_loaded(impl_module) do
      {:module, ^impl_module} -> {:ok, impl_module}
      {:error, _reason} -> :unknown
    end
  end

  defp impl_module(protocol, type_module) do
    Module.concat([protocol, type_module])
  end

  @doc """
  Resolves a protocol call to its implementation function.

  Given a protocol call like `Enum.map(collection, fun)`, resolves to
  the actual implementation function that will be called.

  ## Examples

      iex> alias Litmus.Spike3.ProtocolResolver
      iex> type = {:list, :integer}
      iex> ProtocolResolver.resolve_call(Enum, :map, [type, :any])
      {:ok, {Enumerable.List, :reduce, 3}}

      iex> alias Litmus.Spike3.ProtocolResolver
      iex> ProtocolResolver.resolve_call(Kernel, :to_string, [:integer])
      {:ok, {String.Chars.Integer, :to_string, 1}}
  """
  def resolve_call(module, function, arg_types) do
    # Map common Enum functions to their protocol calls
    case {module, function} do
      # Enum protocol (Enumerable)
      {Enum, :map} ->
        [collection_type | _rest] = arg_types
        resolve_enum_function(collection_type, :reduce)

      {Enum, :filter} ->
        [collection_type | _rest] = arg_types
        resolve_enum_function(collection_type, :reduce)

      {Enum, :reduce} ->
        [collection_type | _rest] = arg_types
        resolve_enum_function(collection_type, :reduce)

      {Enum, :count} ->
        [collection_type] = arg_types
        resolve_enum_function(collection_type, :count)

      {Enum, :member?} ->
        [collection_type | _rest] = arg_types
        resolve_enum_function(collection_type, :member?)

      {Enum, :each} ->
        [collection_type | _rest] = arg_types
        resolve_enum_function(collection_type, :reduce)

      {Enum, :reject} ->
        [collection_type | _rest] = arg_types
        resolve_enum_function(collection_type, :reduce)

      {Enum, :take} ->
        [collection_type | _rest] = arg_types
        resolve_enum_function(collection_type, :reduce)

      {Enum, :drop} ->
        [collection_type | _rest] = arg_types
        resolve_enum_function(collection_type, :reduce)

      {Enum, :into} ->
        [_source_type, target_type | _rest] = arg_types
        resolve_collectable_function(target_type)

      # String.Chars protocol (to_string)
      {Kernel, :to_string} ->
        [value_type] = arg_types
        resolve_string_chars_function(value_type)

      # Inspect protocol (inspect)
      {Kernel, :inspect} ->
        [value_type | _opts] = arg_types
        resolve_inspect_function(value_type)

      _ ->
        :unknown
    end
  end

  defp resolve_enum_function(collection_type, protocol_function) do
    case resolve_impl(Enumerable, collection_type) do
      {:ok, impl_module} ->
        arity = function_arity(protocol_function)
        {:ok, {impl_module, protocol_function, arity}}

      :unknown ->
        :unknown
    end
  end

  defp resolve_string_chars_function(value_type) do
    case resolve_impl(String.Chars, value_type) do
      {:ok, impl_module} ->
        {:ok, {impl_module, :to_string, 1}}

      :unknown ->
        :unknown
    end
  end

  defp resolve_inspect_function(value_type) do
    case resolve_impl(Inspect, value_type) do
      {:ok, impl_module} ->
        # Inspect protocol uses inspect/2 (value, opts)
        {:ok, {impl_module, :inspect, 2}}

      :unknown ->
        :unknown
    end
  end

  defp resolve_collectable_function(target_type) do
    case resolve_impl(Collectable, target_type) do
      {:ok, impl_module} ->
        # Collectable protocol uses into/1
        {:ok, {impl_module, :into, 1}}

      :unknown ->
        :unknown
    end
  end

  defp function_arity(:reduce), do: 3
  defp function_arity(:count), do: 1
  defp function_arity(:member?), do: 2
  defp function_arity(:slice), do: 1
end
