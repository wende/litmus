defmodule Litmus.EffectsSimpleTest do
  use ExUnit.Case, async: true

  import Litmus.Effects

  test "single effect with catch handler" do
    result =
      effect do
        File.read!("test.txt")
      catch
        {File, :read!, ["test.txt"]} -> "mocked content"
      end

    assert result == "mocked content"
  end

  test "external handler" do
    handler = fn
      {File, :read!, _} -> "external"
    end

    result =
      effect(
        do: File.read!("test.txt"),
        catch: handler
      )

    assert result == "external"
  end
end
