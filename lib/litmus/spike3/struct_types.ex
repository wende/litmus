defmodule Litmus.Spike3.StructTypes do
  @moduledoc """
  Struct type tracking for protocol dispatch resolution.

  This module extends the Litmus type system to track specific struct types,
  enabling static resolution of protocol implementations.

  ## Examples

      iex> alias Litmus.Spike3.StructTypes
      iex> StructTypes.struct_type(MyStruct, %{name: :string, age: :integer})
      {:struct, MyStruct, %{name: :string, age: :integer}}

      iex> alias Litmus.Spike3.StructTypes
      iex> StructTypes.extract_struct_module({:struct, User, %{}})
      {:ok, User}

      iex> alias Litmus.Spike3.StructTypes
      iex> StructTypes.is_struct_type?({:struct, MyModule, %{}})
      true
  """

  alias Litmus.Types.Core

  @type struct_field :: {atom(), Core.elixir_type()}
  @type struct_fields :: %{atom() => Core.elixir_type()}

  @doc """
  Creates a struct type.

  ## Parameters
  - module: The struct module (e.g., MyApp.User)
  - fields: Map of field names to types

  ## Examples

      iex> alias Litmus.Spike3.StructTypes
      iex> StructTypes.struct_type(User, %{name: :string, age: :integer})
      {:struct, User, %{name: :string, age: :integer}}
  """
  def struct_type(module, fields \\ %{}) when is_atom(module) and is_map(fields) do
    {:struct, module, fields}
  end

  @doc """
  Checks if a type is a struct type.

  ## Examples

      iex> alias Litmus.Spike3.StructTypes
      iex> StructTypes.is_struct_type?({:struct, MyModule, %{}})
      true

      iex> alias Litmus.Spike3.StructTypes
      iex> StructTypes.is_struct_type?(:string)
      false
  """
  def is_struct_type?({:struct, _module, _fields}), do: true
  def is_struct_type?(_), do: false

  @doc """
  Extracts the module from a struct type.

  ## Examples

      iex> alias Litmus.Spike3.StructTypes
      iex> StructTypes.extract_struct_module({:struct, User, %{}})
      {:ok, User}

      iex> alias Litmus.Spike3.StructTypes
      iex> StructTypes.extract_struct_module(:string)
      :error
  """
  def extract_struct_module({:struct, module, _fields}), do: {:ok, module}
  def extract_struct_module(_), do: :error

  @doc """
  Extracts struct type information from AST patterns.

  Recognizes patterns like:
  - %MyStruct{}
  - %MyStruct{field: value}
  - %{__struct__: MyStruct}

  ## Examples

      # %MyStruct{name: "Alice"}
      iex> alias Litmus.Spike3.StructTypes
      iex> ast = {:%, [], [{:__aliases__, [], [:MyStruct]}, {:%{}, [], [name: "Alice"]}]}
      iex> StructTypes.extract_from_pattern(ast)
      {:ok, {:struct, MyStruct, %{}}}
  """
  def extract_from_pattern(ast) do
    case ast do
      # Pattern: %MyStruct{...}
      {:%, _meta, [module_ast, {:%{}, _, _fields}]} ->
        case extract_module_from_ast(module_ast) do
          {:ok, module} -> {:ok, struct_type(module)}
          :error -> :error
        end

      # Pattern: %{__struct__: MyStruct, ...}
      {:%{}, _meta, fields} when is_list(fields) ->
        case Keyword.get(fields, :__struct__) do
          nil -> :error
          module_ast -> extract_module_from_fields(module_ast)
        end

      _ ->
        :error
    end
  end

  @doc """
  Tracks type through a pipeline operation.

  For pure functions, the type is preserved.
  For transforming functions, infers the result type.

  ## Examples

      iex> alias Litmus.Spike3.StructTypes
      iex> list_type = {:list, :integer}
      iex> StructTypes.propagate_through_pipeline(list_type, {Enum, :map, 2})
      {:list, :any}  # Result is still a list, but element type unknown

      iex> alias Litmus.Spike3.StructTypes
      iex> struct_type = {:struct, User, %{}}
      iex> StructTypes.propagate_through_pipeline(struct_type, {MyModule, :transform, 1})
      :any  # Unknown transformation
  """
  def propagate_through_pipeline(type, {module, function, _arity} = _mfa) do
    cond do
      # Enum.map, filter, etc. preserve collection type
      module == Enum and function in [:map, :filter, :reject, :take, :drop] ->
        preserve_collection_type(type)

      # Enum.into can change collection type
      module == Enum and function == :into ->
        :any

      # Stream operations preserve type
      module == Stream ->
        preserve_collection_type(type)

      # Default: unknown result type
      true ->
        :any
    end
  end

  defp preserve_collection_type({:list, _elem_type}), do: {:list, :any}
  defp preserve_collection_type({:struct, module, _fields}), do: {:struct, module, %{}}
  defp preserve_collection_type({:map, _}), do: {:map, []}
  defp preserve_collection_type(type), do: type

  @doc """
  Infers struct type from a struct literal in AST.

  ## Examples

      # Literal: %MyStruct{name: "Alice", age: 30}
      iex> alias Litmus.Spike3.StructTypes
      iex> ast = {:%, [], [
      ...>   {:__aliases__, [], [:MyStruct]},
      ...>   {:%{}, [], [name: "Alice", age: 30]}
      ...> ]}
      iex> StructTypes.infer_from_literal(ast)
      {:ok, {:struct, MyStruct, %{}}}
  """
  def infer_from_literal({:%, _meta, [module_ast, {:%{}, _, _fields}]}) do
    case extract_module_from_ast(module_ast) do
      {:ok, module} -> {:ok, struct_type(module)}
      :error -> :error
    end
  end

  def infer_from_literal(_), do: :error

  @doc """
  Infers type from common Elixir expressions.

  ## Examples

      iex> alias Litmus.Spike3.StructTypes
      iex> StructTypes.infer_from_expression([1, 2, 3])
      {:list, :integer}

      iex> alias Litmus.Spike3.StructTypes
      iex> StructTypes.infer_from_expression({:%{}, [], [a: 1, b: 2]})
      {:map, []}

      iex> alias Litmus.Spike3.StructTypes
      iex> StructTypes.infer_from_expression({:.., [], [1, 10]})
      {:struct, Range, %{}}
  """
  def infer_from_expression(ast) do
    case ast do
      # List literal: [1, 2, 3]
      list when is_list(list) ->
        elem_type = infer_list_element_type(list)
        {:list, elem_type}

      # Map literal: %{a: 1, b: 2}
      {:%{}, _meta, _fields} ->
        {:map, []}

      # Range: 1..10
      {:.., _meta, [_start, _end]} ->
        struct_type(Range)

      # Struct literal: %MyStruct{}
      {:%, _meta, _args} = struct_ast ->
        case infer_from_literal(struct_ast) do
          {:ok, type} -> type
          :error -> :any
        end

      # Function call - check for known constructors
      {{:., _, [module_ast, function]}, _, _args} ->
        case {extract_module_from_ast(module_ast), function} do
          {{:ok, MapSet}, :new} -> struct_type(MapSet)
          {{:ok, Range}, :new} -> struct_type(Range)
          {{:ok, module}, :new} -> struct_type(module)
          _ -> :any
        end

      _ ->
        :any
    end
  end

  defp infer_list_element_type([]), do: :any

  defp infer_list_element_type([first | _rest]) when is_integer(first), do: :integer
  defp infer_list_element_type([first | _rest]) when is_binary(first), do: :string
  defp infer_list_element_type([first | _rest]) when is_atom(first), do: :atom
  defp infer_list_element_type(_), do: :any

  # Helper: Extract module from AST
  defp extract_module_from_ast({:__aliases__, _meta, parts}) when is_list(parts) do
    module = Module.concat(parts)
    {:ok, module}
  end

  defp extract_module_from_ast(module) when is_atom(module) do
    {:ok, module}
  end

  defp extract_module_from_ast(_), do: :error

  defp extract_module_from_fields(module_ast) when is_atom(module_ast) do
    {:ok, struct_type(module_ast)}
  end

  defp extract_module_from_fields({:__aliases__, _, parts}) do
    module = Module.concat(parts)
    {:ok, struct_type(module)}
  end

  defp extract_module_from_fields(_), do: :error
end
