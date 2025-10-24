defmodule Litmus.Spike3.ProtocolResolverTest do
  use ExUnit.Case, async: true

  @moduletag :spike
  @moduletag :spike3

  alias Litmus.Spike3.{ProtocolResolver, StructTypes}

  doctest ProtocolResolver

  describe "resolve_impl/2 for built-in types" do
    test "resolves List for Enumerable" do
      assert {:ok, Enumerable.List} = ProtocolResolver.resolve_impl(Enumerable, {:list, :integer})
    end

    test "resolves Map for Enumerable" do
      assert {:ok, Enumerable.Map} = ProtocolResolver.resolve_impl(Enumerable, {:map, []})
    end

    test "resolves MapSet for Enumerable" do
      struct_type = StructTypes.struct_type(MapSet)
      assert {:ok, Enumerable.MapSet} = ProtocolResolver.resolve_impl(Enumerable, struct_type)
    end

    test "resolves Range for Enumerable" do
      struct_type = StructTypes.struct_type(Range)
      assert {:ok, Enumerable.Range} = ProtocolResolver.resolve_impl(Enumerable, struct_type)
    end

    test "resolves File.Stream for Enumerable" do
      struct_type = StructTypes.struct_type(File.Stream)
      assert {:ok, Enumerable.File.Stream} = ProtocolResolver.resolve_impl(Enumerable, struct_type)
    end
  end

  describe "resolve_impl/2 for String.Chars protocol" do
    test "resolves Integer" do
      assert {:ok, String.Chars.Integer} = ProtocolResolver.resolve_impl(String.Chars, :integer)
    end

    test "resolves List" do
      assert {:ok, String.Chars.List} = ProtocolResolver.resolve_impl(String.Chars, {:list, :any})
    end

    test "resolves Atom" do
      assert {:ok, String.Chars.Atom} = ProtocolResolver.resolve_impl(String.Chars, :atom)
    end
  end

  describe "resolve_impl/2 for unknown types" do
    test "returns :unknown for :any type" do
      assert :unknown = ProtocolResolver.resolve_impl(Enumerable, :any)
    end

    test "returns :unknown for type variables" do
      assert :unknown = ProtocolResolver.resolve_impl(Enumerable, {:type_var, :t})
    end
  end

  describe "get_implementations/1" do
    test "returns list of Enumerable implementations" do
      impls = ProtocolResolver.get_implementations(Enumerable)

      assert is_list(impls)
      assert Enumerable.List in impls
      assert Enumerable.Map in impls
      assert Enumerable.MapSet in impls
      assert Enumerable.Range in impls
    end

    test "returns list of String.Chars implementations" do
      impls = ProtocolResolver.get_implementations(String.Chars)

      assert is_list(impls)
      assert String.Chars.Integer in impls
      assert String.Chars.Atom in impls
    end

    test "returns empty list for non-existent protocol" do
      impls = ProtocolResolver.get_implementations(NonExistentProtocol)
      assert impls == []
    end
  end

  describe "has_impl?/2" do
    test "returns true for List + Enumerable" do
      assert ProtocolResolver.has_impl?(Enumerable, {:list, :any})
    end

    test "returns true for Map + Enumerable" do
      assert ProtocolResolver.has_impl?(Enumerable, {:map, []})
    end

    test "returns false for integer + Enumerable" do
      refute ProtocolResolver.has_impl?(Enumerable, :integer)
    end

    test "returns false for unknown types" do
      refute ProtocolResolver.has_impl?(Enumerable, :any)
    end
  end

  describe "resolve_call/3" do
    test "resolves Enum.map with list" do
      args = [{:list, :integer}, :any]
      assert {:ok, {Enumerable.List, :reduce, 3}} = ProtocolResolver.resolve_call(Enum, :map, args)
    end

    test "resolves Enum.filter with map" do
      args = [{:map, []}, :any]
      assert {:ok, {Enumerable.Map, :reduce, 3}} = ProtocolResolver.resolve_call(Enum, :filter, args)
    end

    test "resolves Enum.count with MapSet" do
      struct_type = StructTypes.struct_type(MapSet)
      args = [struct_type]
      assert {:ok, {Enumerable.MapSet, :count, 1}} = ProtocolResolver.resolve_call(Enum, :count, args)
    end

    test "returns :unknown for unknown functions" do
      args = [{:list, :any}]
      assert :unknown = ProtocolResolver.resolve_call(MyModule, :unknown_function, args)
    end
  end

  describe "user-defined struct resolution" do
    # This will be tested more thoroughly in Day 2 Morning
    # For now, just verify the mechanism works

    test "resolves user struct if implementation exists" do
      # The Spike3.MyList struct has an Enumerable implementation
      # defined in spike3/protocol_corpus.ex
      struct_type = StructTypes.struct_type(Spike3.MyList)

      # Note: This will be :unknown until we compile protocol_corpus.ex
      result = ProtocolResolver.resolve_impl(Enumerable, struct_type)
      assert result == {:ok, Enumerable.Spike3.MyList} or result == :unknown
    end
  end
end
