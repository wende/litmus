defmodule Litmus.Registry.BottommostTest do
  use ExUnit.Case
  alias Litmus.Effects.Registry

  test "File.write/2 resolution chain" do
    result = Registry.resolve_to_leaves({File, :write, 2})
    IO.puts("\nFile.write/2 resolves to:")
    IO.inspect(result, pretty: true)
  end

  test "File.write/3 resolution chain" do
    result = Registry.resolve_to_leaves({File, :write, 3})
    IO.puts("\nFile.write/3 resolves to:")
    IO.inspect(result, pretty: true)
  end

  test "File.write!/2 resolution chain" do
    result = Registry.resolve_to_leaves({File, :write!, 2})
    IO.puts("\nFile.write!/2 resolves to:")
    IO.inspect(result, pretty: true)
  end

  test "Check if File.write/3 is in effects map (is it bottommost?)" do
    effect = Registry.effect_type({File, :write, 3})
    IO.puts("\nFile.write/3 effect type: #{inspect(effect)}")

    # If it has an effect type, it's considered bottommost
    assert effect == :s, "File.write/3 should be side effect"
  end

  test "Check what :file module functions exist in resolution" do
    # Check if any :file (Erlang) functions show up
    IO.puts("\nChecking Erlang :file module...")

    result = Registry.resolve_to_leaves({File, :write, 3})
    case result do
      {:ok, leaves} ->
        erlang_funcs = Enum.filter(leaves, fn {mod, _, _} -> mod == :file end)
        IO.puts("Erlang :file functions in leaves: #{inspect(erlang_funcs)}")

      :not_found ->
        IO.puts("File.write/3 does not resolve further")
    end
  end
end
