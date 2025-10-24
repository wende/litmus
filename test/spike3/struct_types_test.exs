defmodule Litmus.Spike3.StructTypesTest do
  use ExUnit.Case, async: true

  @moduletag :spike
  @moduletag :spike3

  alias Litmus.Spike3.StructTypes

  doctest StructTypes

  describe "struct_type/2" do
    test "creates a struct type with module and fields" do
      type = StructTypes.struct_type(User, %{name: :string, age: :integer})
      assert type == {:struct, User, %{name: :string, age: :integer}}
    end

    test "creates a struct type with empty fields" do
      type = StructTypes.struct_type(MyModule)
      assert type == {:struct, MyModule, %{}}
    end
  end

  describe "is_struct_type?/1" do
    test "returns true for struct types" do
      type = {:struct, User, %{}}
      assert StructTypes.is_struct_type?(type)
    end

    test "returns false for primitive types" do
      refute StructTypes.is_struct_type?(:string)
      refute StructTypes.is_struct_type?(:integer)
      refute StructTypes.is_struct_type?({:list, :any})
    end
  end

  describe "extract_struct_module/1" do
    test "extracts module from struct type" do
      type = {:struct, User, %{name: :string}}
      assert StructTypes.extract_struct_module(type) == {:ok, User}
    end

    test "returns error for non-struct types" do
      assert StructTypes.extract_struct_module(:string) == :error
      assert StructTypes.extract_struct_module({:list, :any}) == :error
    end
  end

  describe "extract_from_pattern/1" do
    test "extracts struct type from %MyStruct{} pattern" do
      # AST for: %User{}
      ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}

      assert StructTypes.extract_from_pattern(ast) == {:ok, {:struct, User, %{}}}
    end

    test "extracts struct type from pattern with fields" do
      # AST for: %User{name: x, age: y}
      ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], [name: {:x, [], nil}, age: {:y, [], nil}]}]}

      assert StructTypes.extract_from_pattern(ast) == {:ok, {:struct, User, %{}}}
    end

    test "extracts struct type from %{__struct__: Module} pattern" do
      # AST for: %{__struct__: User}
      ast = {:%{}, [], [__struct__: {:__aliases__, [], [:User]}]}

      assert StructTypes.extract_from_pattern(ast) == {:ok, {:struct, User, %{}}}
    end

    test "returns error for non-struct patterns" do
      # Regular map: %{a: 1}
      ast = {:%{}, [], [a: 1]}
      assert StructTypes.extract_from_pattern(ast) == :error

      # List
      ast = [1, 2, 3]
      assert StructTypes.extract_from_pattern(ast) == :error
    end
  end

  describe "propagate_through_pipeline/2" do
    test "preserves list type through Enum.map" do
      list_type = {:list, :integer}
      result = StructTypes.propagate_through_pipeline(list_type, {Enum, :map, 2})

      assert result == {:list, :any}
    end

    test "preserves struct type through Enum.filter" do
      struct_type = {:struct, User, %{name: :string}}
      result = StructTypes.propagate_through_pipeline(struct_type, {Enum, :filter, 2})

      assert result == {:struct, User, %{}}
    end

    test "returns :any for unknown transformations" do
      list_type = {:list, :integer}
      result = StructTypes.propagate_through_pipeline(list_type, {MyModule, :unknown, 1})

      assert result == :any
    end

    test "preserves type through Stream operations" do
      list_type = {:list, :string}
      result = StructTypes.propagate_through_pipeline(list_type, {Stream, :map, 2})

      assert result == {:list, :any}
    end
  end

  describe "infer_from_literal/1" do
    test "infers struct type from literal" do
      # AST for: %User{name: "Alice"}
      ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], [name: "Alice"]}]}

      assert StructTypes.infer_from_literal(ast) == {:ok, {:struct, User, %{}}}
    end

    test "returns error for non-struct literals" do
      assert StructTypes.infer_from_literal([1, 2, 3]) == :error
      assert StructTypes.infer_from_literal({:%{}, [], []}) == :error
    end
  end

  describe "infer_from_expression/1" do
    test "infers list type from list literal" do
      assert StructTypes.infer_from_expression([1, 2, 3]) == {:list, :integer}
      assert StructTypes.infer_from_expression(["a", "b"]) == {:list, :string}
      assert StructTypes.infer_from_expression([:a, :b]) == {:list, :atom}
    end

    test "infers map type from map literal" do
      ast = {:%{}, [], [a: 1, b: 2]}
      assert StructTypes.infer_from_expression(ast) == {:map, []}
    end

    test "infers Range type from range expression" do
      ast = {:.., [], [1, 10]}
      assert StructTypes.infer_from_expression(ast) == {:struct, Range, %{}}
    end

    test "infers MapSet type from MapSet.new()" do
      ast = {{:., [], [{:__aliases__, [], [:MapSet]}, :new]}, [], [[1, 2, 3]]}
      assert StructTypes.infer_from_expression(ast) == {:struct, MapSet, %{}}
    end

    test "infers struct type from struct literal" do
      ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}
      assert StructTypes.infer_from_expression(ast) == {:struct, User, %{}}
    end

    test "returns :any for unknown expressions" do
      assert StructTypes.infer_from_expression({:unknown, [], []}) == :any
    end
  end
end
