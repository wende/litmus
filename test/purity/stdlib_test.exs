defmodule Litmus.StdlibTest do
  use ExUnit.Case, async: true
  alias Litmus.Stdlib

  describe "whitelisted?/1" do
    test "returns true for whitelisted Enum functions" do
      assert Stdlib.whitelisted?({Enum, :map, 2})
      assert Stdlib.whitelisted?({Enum, :filter, 2})
      assert Stdlib.whitelisted?({Enum, :reduce, 3})
      assert Stdlib.whitelisted?({Enum, :count, 1})
    end

    test "returns true for all List functions" do
      assert Stdlib.whitelisted?({List, :first, 1})
      assert Stdlib.whitelisted?({List, :last, 1})
      assert Stdlib.whitelisted?({List, :flatten, 1})
      assert Stdlib.whitelisted?({List, :zip, 2})
    end

    test "returns true for Integer functions" do
      assert Stdlib.whitelisted?({Integer, :to_string, 1})
      assert Stdlib.whitelisted?({Integer, :digits, 1})
      assert Stdlib.whitelisted?({Integer, :parse, 1})
    end

    test "returns true for Float functions" do
      assert Stdlib.whitelisted?({Float, :round, 1})
      assert Stdlib.whitelisted?({Float, :ceil, 1})
      assert Stdlib.whitelisted?({Float, :floor, 1})
    end

    test "returns true for String functions except atom conversions" do
      # These should be whitelisted
      assert Stdlib.whitelisted?({String, :upcase, 1})
      assert Stdlib.whitelisted?({String, :downcase, 1})
      assert Stdlib.whitelisted?({String, :reverse, 1})
      assert Stdlib.whitelisted?({String, :slice, 2})

      # These should NOT be whitelisted (mutate atom table)
      refute Stdlib.whitelisted?({String, :to_atom, 1})
      refute Stdlib.whitelisted?({String, :to_existing_atom, 1})
    end

    test "returns true for Date/Time functions except now/utc_now" do
      assert Stdlib.whitelisted?({Date, :new, 3})
      assert Stdlib.whitelisted?({Date, :add, 2})
      assert Stdlib.whitelisted?({Time, :new, 4})

      # These depend on system time - not pure
      refute Stdlib.whitelisted?({DateTime, :now, 2})
      refute Stdlib.whitelisted?({DateTime, :utc_now, 0})
      refute Stdlib.whitelisted?({NaiveDateTime, :local_now, 0})
      refute Stdlib.whitelisted?({NaiveDateTime, :utc_now, 0})
    end

    test "returns true for Kernel arithmetic operators" do
      assert Stdlib.whitelisted?({Kernel, :+, 2})
      assert Stdlib.whitelisted?({Kernel, :-, 2})
      assert Stdlib.whitelisted?({Kernel, :*, 2})
      assert Stdlib.whitelisted?({Kernel, :/, 2})
      assert Stdlib.whitelisted?({Kernel, :div, 2})
      assert Stdlib.whitelisted?({Kernel, :rem, 2})
    end

    test "returns true for Kernel comparison operators" do
      assert Stdlib.whitelisted?({Kernel, :==, 2})
      assert Stdlib.whitelisted?({Kernel, :!=, 2})
      assert Stdlib.whitelisted?({Kernel, :===, 2})
      assert Stdlib.whitelisted?({Kernel, :!==, 2})
      assert Stdlib.whitelisted?({Kernel, :<, 2})
      assert Stdlib.whitelisted?({Kernel, :>, 2})
      assert Stdlib.whitelisted?({Kernel, :<=, 2})
      assert Stdlib.whitelisted?({Kernel, :>=, 2})
    end

    test "returns true for Kernel type checks" do
      assert Stdlib.whitelisted?({Kernel, :is_atom, 1})
      assert Stdlib.whitelisted?({Kernel, :is_binary, 1})
      assert Stdlib.whitelisted?({Kernel, :is_integer, 1})
      assert Stdlib.whitelisted?({Kernel, :is_list, 1})
      assert Stdlib.whitelisted?({Kernel, :is_map, 1})
      assert Stdlib.whitelisted?({Kernel, :is_tuple, 1})
    end

    test "returns false for I/O operations" do
      refute Stdlib.whitelisted?({IO, :puts, 1})
      refute Stdlib.whitelisted?({IO, :inspect, 1})
      refute Stdlib.whitelisted?({IO, :read, 2})
      refute Stdlib.whitelisted?({IO, :write, 2})
    end

    test "returns false for File operations" do
      refute Stdlib.whitelisted?({File, :read, 1})
      refute Stdlib.whitelisted?({File, :write, 2})
      refute Stdlib.whitelisted?({File, :exists?, 1})
    end

    test "returns false for System operations" do
      refute Stdlib.whitelisted?({System, :get_env, 1})
      refute Stdlib.whitelisted?({System, :cmd, 2})
      refute Stdlib.whitelisted?({System, :version, 0})
    end

    test "returns false for Process operations" do
      refute Stdlib.whitelisted?({Process, :send, 2})
      refute Stdlib.whitelisted?({Process, :spawn, 1})
      refute Stdlib.whitelisted?({Process, :get, 0})
      refute Stdlib.whitelisted?({Process, :put, 2})
    end

    test "returns false for Kernel side-effect operations" do
      refute Stdlib.whitelisted?({Kernel, :send, 2})
      refute Stdlib.whitelisted?({Kernel, :spawn, 1})
      refute Stdlib.whitelisted?({Kernel, :apply, 2})
      refute Stdlib.whitelisted?({Kernel, :raise, 1})
    end

    test "returns false for unknown modules" do
      refute Stdlib.whitelisted?({UnknownModule, :foo, 1})
      refute Stdlib.whitelisted?({MyApp.Module, :bar, 2})
    end

    test "returns false for unknown functions in whitelisted modules" do
      # Kernel has selective whitelist, so unknown functions should be false
      refute Stdlib.whitelisted?({Kernel, :unknown_function, 99})
    end

    test "handles invalid MFA tuples gracefully" do
      # These should all return false (not raise)
      refute Stdlib.whitelisted?({:not_a_module, :func, 1})
      refute Stdlib.whitelisted?({String, "not_atom", 1})
    end
  end

  describe "get_module_whitelist/1" do
    test "returns :all for fully whitelisted modules" do
      assert Stdlib.get_module_whitelist(List) == :all
      assert Stdlib.get_module_whitelist(Tuple) == :all
      assert Stdlib.get_module_whitelist(Float) == :all
    end

    test "returns {:all_except, exceptions} for modules with exceptions" do
      assert {:all_except, exceptions} = Stdlib.get_module_whitelist(String)
      assert {:to_atom, 1} in exceptions
      assert {:to_existing_atom, 1} in exceptions
    end

    test "returns function map for selective whitelists" do
      assert is_map(Stdlib.get_module_whitelist(Kernel))
      kernel_whitelist = Stdlib.get_module_whitelist(Kernel)
      assert is_list(kernel_whitelist[:+])
      assert 2 in kernel_whitelist[:+]
    end

    test "returns nil for non-whitelisted modules" do
      assert Stdlib.get_module_whitelist(IO) == nil
      assert Stdlib.get_module_whitelist(File) == nil
      assert Stdlib.get_module_whitelist(System) == nil
      assert Stdlib.get_module_whitelist(UnknownModule) == nil
    end
  end

  describe "whitelisted_modules/0" do
    test "returns list of whitelisted modules" do
      modules = Stdlib.whitelisted_modules()
      assert is_list(modules)
      assert Enum in modules
      assert List in modules
      assert String in modules
      assert Kernel in modules
      refute IO in modules
      refute File in modules
    end

    test "returns non-empty list" do
      assert length(Stdlib.whitelisted_modules()) > 10
    end
  end

  describe "count_whitelisted/1" do
    test "returns :many for :all rules" do
      assert Stdlib.count_whitelisted(List) == :many
      assert Stdlib.count_whitelisted(Float) == :many
    end

    test "returns :many for {:all_except, _} rules" do
      assert Stdlib.count_whitelisted(Enum) == :many
      assert Stdlib.count_whitelisted(String) == :many
    end

    test "returns integer for selective whitelists" do
      count = Stdlib.count_whitelisted(Kernel)
      assert is_integer(count)
      # Kernel has many whitelisted functions
      assert count > 30
    end

    test "returns 0 for non-whitelisted modules" do
      assert Stdlib.count_whitelisted(IO) == 0
      assert Stdlib.count_whitelisted(File) == 0
    end
  end

  describe "expand_rule/2" do
    test "expands :all rule to list of MFAs" do
      mfas = Stdlib.expand_rule(Integer, :all)
      assert is_list(mfas)
      assert length(mfas) > 0
      assert {Integer, :to_string, 1} in mfas
      assert {Integer, :digits, 1} in mfas
    end

    test "expands {:all_except, _} rule correctly" do
      exceptions = [{:to_atom, 1}, {:to_existing_atom, 1}]
      mfas = Stdlib.expand_rule(String, {:all_except, exceptions})
      assert is_list(mfas)

      # Should include normal string functions
      assert {String, :upcase, 1} in mfas
      assert {String, :downcase, 1} in mfas

      # Should NOT include exceptions
      refute {String, :to_atom, 1} in mfas
      refute {String, :to_existing_atom, 1} in mfas
    end

    test "expands function map to list of MFAs" do
      function_map = %{
        foo: [1, 2],
        bar: [3]
      }

      mfas = Stdlib.expand_rule(TestModule, function_map)
      assert {TestModule, :foo, 1} in mfas
      assert {TestModule, :foo, 2} in mfas
      assert {TestModule, :bar, 3} in mfas
      assert length(mfas) == 3
    end
  end

  describe "whitelist coverage" do
    test "covers major Elixir stdlib modules" do
      whitelist = Stdlib.whitelist()

      # Core data structures
      assert Map.has_key?(whitelist, Enum)
      assert Map.has_key?(whitelist, List)
      assert Map.has_key?(whitelist, Map)
      assert Map.has_key?(whitelist, Tuple)
      assert Map.has_key?(whitelist, MapSet)
      assert Map.has_key?(whitelist, Keyword)

      # String and numeric
      assert Map.has_key?(whitelist, String)
      assert Map.has_key?(whitelist, Integer)
      assert Map.has_key?(whitelist, Float)

      # Date/Time
      assert Map.has_key?(whitelist, Date)
      assert Map.has_key?(whitelist, Time)
      assert Map.has_key?(whitelist, DateTime)

      # Utilities
      assert Map.has_key?(whitelist, Path)
      assert Map.has_key?(whitelist, URI)
      assert Map.has_key?(whitelist, Regex)
    end

    test "excludes side-effect modules" do
      whitelist = Stdlib.whitelist()

      refute Map.has_key?(whitelist, IO)
      refute Map.has_key?(whitelist, File)
      refute Map.has_key?(whitelist, System)
      refute Map.has_key?(whitelist, Process)
      refute Map.has_key?(whitelist, Agent)
      refute Map.has_key?(whitelist, Task)
    end
  end

  describe "edge cases" do
    test "handles module without __info__/1 gracefully" do
      # Non-existent module should return empty list
      mfas = Stdlib.expand_rule(NonExistentModule, :all)
      assert mfas == []
    end

    test "whitelist is deterministic" do
      # Calling whitelist() multiple times should return same structure
      w1 = Stdlib.whitelist()
      w2 = Stdlib.whitelist()
      assert w1 == w2
    end
  end
end
