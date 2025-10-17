defmodule Litmus.EffectsErrorTest do
  use ExUnit.Case, async: true

  import Litmus.Effects
  alias Litmus.Effects.UnhandledError

  describe "unhandled effects" do
    test "inline handler raises UnhandledError with helpful message" do
      assert_raise UnhandledError, fn ->
        effect do
          File.read!("test.txt")
        catch
          {File, :write!, _} -> :ok
        end
      end
    end

    test "external handler raises UnhandledError with helpful message" do
      handler = fn
        {File, :read!, _} -> "handled"
      end

      assert_raise UnhandledError, fn ->
        effect(
          do: File.write!("test.txt", "data"),
          catch: handler
        )
      end
    end

    test "UnhandledError contains effect signature details" do
      try do
        effect do
          File.read!("config.json")
        catch
          {IO, :puts, _} -> :ok
        end
      rescue
        e in UnhandledError ->
          assert e.effect == {File, :read!}
          assert e.args == ["config.json"]
          assert e.message =~ "File.read!/1"
          assert e.message =~ ~s({File, :read!, ["config.json"]})
          assert e.message =~ "Unhandled effect"
      end
    end

    test "error message provides helpful suggestions" do
      try do
        effect do
          File.read!("test.txt")
        catch
          {File, :write!, _} -> :ok
        end
      rescue
        e in UnhandledError ->
          assert e.message =~ "Add a matching pattern"
          assert e.message =~ "Litmus.Effects.apply_effect"
          assert e.message =~ "wildcard pattern"
      end
    end

    test "UnhandledError preserves stacktrace" do
      try do
        effect do
          File.read!("test.txt")
        catch
          {File, :write!, _} -> :ok
        end
      rescue
        _e in UnhandledError ->
          stacktrace = __STACKTRACE__
          assert is_list(stacktrace)
          assert length(stacktrace) > 0
      end
    end
  end

  describe "handled effects" do
    test "properly handled effects don't raise UnhandledError" do
      result =
        effect do
          File.read!("test.txt")
        catch
          {File, :read!, _} -> "mocked"
        end

      assert result == "mocked"
    end

    test "wildcard patterns prevent UnhandledError" do
      result =
        effect do
          File.read!("test.txt")
        catch
          {File, :write!, _} -> :written
          _ -> :default
        end

      assert result == :default
    end

    test "passthrough pattern prevents UnhandledError" do
      result =
        effect do
          File.read!("test/effects/effects_error_test.exs")
        catch
          {File, :write!, _} -> :written
          effect_sig -> Litmus.Effects.apply_effect(effect_sig)
        end

      assert is_binary(result)
      assert byte_size(result) > 0
    end
  end
end
