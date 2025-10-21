defmodule Litmus.Registry.BottommostTest do
  use ExUnit.Case
  alias Litmus.Effects.Registry

  test "File.write/2 resolution chain" do
    result = Registry.resolve_to_leaves({File, :write, 2})
    assert {:ok, _leaves} = result
  end

  test "File.write/3 resolution chain" do
    result = Registry.resolve_to_leaves({File, :write, 3})
    assert {:ok, _leaves} = result
  end

  test "File.write!/2 resolution chain" do
    result = Registry.resolve_to_leaves({File, :write!, 2})
    assert {:ok, _leaves} = result
  end

  test "Check if File.write/3 is in effects map (is it bottommost?)" do
    effect = Registry.effect_type({File, :write, 3})

    # If it has an effect type, it's considered bottommost
    assert effect == :s, "File.write/3 should be side effect"
  end

  test "Check what :file module functions exist in resolution" do
    # Check if any :file (Erlang) functions show up
    result = Registry.resolve_to_leaves({File, :write, 3})
    assert {:ok, _leaves} = result
  end
end
