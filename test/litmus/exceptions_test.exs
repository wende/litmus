defmodule Litmus.ExceptionsTest do
  use ExUnit.Case, async: true
  doctest Litmus.Exceptions

  alias Litmus.Exceptions

  describe "empty/0" do
    test "creates exception info with no exceptions" do
      assert Exceptions.empty() == %{
               errors: MapSet.new(),
               non_errors: false
             }
    end

    test "empty exceptions are pure" do
      assert Exceptions.pure?(Exceptions.empty())
    end
  end

  describe "error/1" do
    test "creates exception info for a single exception module" do
      info = Exceptions.error(ArgumentError)

      assert info.errors == MapSet.new([ArgumentError])
      assert info.non_errors == false
    end

    test "can check if specific exception can be raised" do
      info = Exceptions.error(ArgumentError)

      assert Exceptions.can_raise?(info, ArgumentError)
      refute Exceptions.can_raise?(info, KeyError)
    end
  end

  describe "error_unknown/0" do
    test "creates exception info for unknown exceptions" do
      info = Exceptions.error_unknown()

      assert info.errors == :unknown
      assert info.non_errors == false
    end

    test "unknown errors can raise any exception" do
      info = Exceptions.error_unknown()

      assert Exceptions.can_raise?(info, ArgumentError)
      assert Exceptions.can_raise?(info, KeyError)
      assert Exceptions.can_raise?(info, RuntimeError)
    end
  end

  describe "non_error/0" do
    test "creates exception info for throw/exit" do
      info = Exceptions.non_error()

      assert info.errors == MapSet.new()
      assert info.non_errors == true
    end

    test "can detect throw/exit capability" do
      info = Exceptions.non_error()

      assert Exceptions.can_throw_or_exit?(info)
    end
  end

  describe "merge/2" do
    test "merges error sets" do
      info1 = Exceptions.error(ArgumentError)
      info2 = Exceptions.error(KeyError)

      merged = Exceptions.merge(info1, info2)

      assert merged.errors == MapSet.new([ArgumentError, KeyError])
      assert merged.non_errors == false
    end

    test "merges non_errors flags" do
      info1 = Exceptions.error(ArgumentError)
      info2 = Exceptions.non_error()

      merged = Exceptions.merge(info1, info2)

      assert merged.errors == MapSet.new([ArgumentError])
      assert merged.non_errors == true
    end

    test "unknown errors propagate" do
      info1 = Exceptions.error_unknown()
      info2 = Exceptions.error(KeyError)

      merged = Exceptions.merge(info1, info2)

      assert merged.errors == :unknown
    end

    test "merging with empty is identity" do
      info = Exceptions.error(ArgumentError)
      empty = Exceptions.empty()

      assert Exceptions.merge(info, empty) == info
      assert Exceptions.merge(empty, info) == info
    end
  end

  describe "merge_all/1" do
    test "merges multiple exception infos" do
      infos = [
        Exceptions.error(ArgumentError),
        Exceptions.error(KeyError),
        Exceptions.non_error()
      ]

      merged = Exceptions.merge_all(infos)

      assert merged.errors == MapSet.new([ArgumentError, KeyError])
      assert merged.non_errors == true
    end

    test "handles empty list" do
      assert Exceptions.merge_all([]) == Exceptions.empty()
    end
  end

  describe "pure?/1" do
    test "empty exceptions are pure" do
      assert Exceptions.pure?(Exceptions.empty())
    end

    test "errors make function impure" do
      refute Exceptions.pure?(Exceptions.error(ArgumentError))
    end

    test "non_errors make function impure" do
      refute Exceptions.pure?(Exceptions.non_error())
    end

    test "unknown errors make function impure" do
      refute Exceptions.pure?(Exceptions.error_unknown())
    end
  end

  describe "subtract/2" do
    test "subtracts caught errors from error set" do
      info = %{
        errors: MapSet.new([ArgumentError, KeyError, RuntimeError]),
        non_errors: false
      }

      caught = %{
        errors: MapSet.new([ArgumentError, KeyError]),
        non_errors: false
      }

      result = Exceptions.subtract(info, caught)

      assert result.errors == MapSet.new([RuntimeError])
      assert result.non_errors == false
    end

    test "removes non_errors flag when caught" do
      info = %{errors: MapSet.new(), non_errors: true}
      caught = %{errors: MapSet.new(), non_errors: true}

      result = Exceptions.subtract(info, caught)

      assert result.errors == MapSet.new()
      assert result.non_errors == false
    end

    test "preserves non_errors flag when not caught" do
      info = %{errors: MapSet.new([ArgumentError]), non_errors: true}
      caught = %{errors: MapSet.new([ArgumentError]), non_errors: false}

      result = Exceptions.subtract(info, caught)

      assert result.errors == MapSet.new()
      assert result.non_errors == true
    end

    test "unknown errors stay unknown after subtraction" do
      info = %{errors: :unknown, non_errors: false}
      caught = %{errors: MapSet.new([ArgumentError]), non_errors: false}

      result = Exceptions.subtract(info, caught)

      assert result.errors == :unknown
    end

    test "subtracting from known errors preserves them when unknown is caught" do
      info = %{errors: MapSet.new([ArgumentError, KeyError]), non_errors: false}
      caught = %{errors: :unknown, non_errors: false}

      result = Exceptions.subtract(info, caught)

      # Can't know what was caught, so keep the original set
      assert result.errors == MapSet.new([ArgumentError, KeyError])
    end
  end
end
