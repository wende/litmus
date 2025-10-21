defmodule Litmus.Registry.EnumMapTest do
  use ExUnit.Case
  alias Litmus.Effects.Registry
  alias Litmus.Types.Effects

  test "Enum.map/2 direct effect type" do
    result = Registry.effect_type({Enum, :map, 2})
    assert result == :l
  end

  test "Enum.map/2 from_mfa" do
    effect = Effects.from_mfa({Enum, :map, 2})
    assert match?({:effect_label, :lambda}, effect)
  end
end
