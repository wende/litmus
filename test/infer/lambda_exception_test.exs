defmodule LambdaExceptionTest do
  use ExUnit.Case
  alias Litmus.Analyzer.ASTWalker
  alias Litmus.Types.Core

  @moduletag :lambda_exception_debug

  test "lambda with if and raise has exception in body effect" do
    source = """
    defmodule TestModule do
      def lambda_with_if_raise do
        fn item ->
          if item < 0 do
            raise ArgumentError, "negative"
          else
            item * 2
          end
        end
      end
    end
    """

    {:ok, ast} = Code.string_to_quoted(source)
    {:ok, result} = ASTWalker.analyze_ast(ast)

    func = result.functions[{TestModule, :lambda_with_if_raise, 0}]
    assert func != nil, "Function should be found"

    # The function returns a lambda, so outer effect should be empty/pure
    compact = Core.to_compact_effect(func.effect)
    assert compact == :p, "Function returning lambda should be pure, got: #{inspect(compact)}"

    # Check the function type - the lambda's effect should be inside
    IO.puts("\nFunction type: #{inspect(func.type, pretty: true)}")
    IO.puts("Function effect: #{inspect(func.effect, pretty: true)}")
  end

  test "Enum.filter with lambda containing raise propagates exception" do
    source = """
    defmodule TestModule do
      def filter_with_raise(list) do
        Enum.filter(list, fn item ->
          if item < 0 do
            raise ArgumentError, "negative"
          else
            item > 5
          end
        end)
      end
    end
    """

    {:ok, ast} = Code.string_to_quoted(source)
    {:ok, result} = ASTWalker.analyze_ast(ast)

    func = result.functions[{TestModule, :filter_with_raise, 1}]
    assert func != nil, "Function should be found"

    compact = Core.to_compact_effect(func.effect)

    IO.puts("\nEnum.filter function:")
    IO.puts("  Type: #{inspect(func.type, pretty: true)}")
    IO.puts("  Effect: #{inspect(func.effect, pretty: true)}")
    IO.puts("  Compact: #{inspect(compact)}")
    IO.puts("  Calls: #{inspect(func.calls)}")

    # This should propagate the exception from the lambda
    case compact do
      {:e, types} ->
        assert "Elixir.ArgumentError" in types,
               "Expected ArgumentError in #{inspect(types)}"

      :u ->
        flunk("Function shows as unknown - lambda effect not propagated")

      other ->
        flunk("Expected exception effect, got: #{inspect(other)}")
    end
  end

  test "Enum.map with simple raise propagates exception" do
    source = """
    defmodule TestModule do
      def map_with_raise(list) do
        Enum.map(list, fn item ->
          if item == nil do
            raise ArgumentError, "nil"
          else
            item * 2
          end
        end)
      end
    end
    """

    {:ok, ast} = Code.string_to_quoted(source)
    {:ok, result} = ASTWalker.analyze_ast(ast)

    func = result.functions[{TestModule, :map_with_raise, 1}]
    assert func != nil, "Function should be found"

    compact = Core.to_compact_effect(func.effect)

    IO.puts("\nEnum.map function:")
    IO.puts("  Compact: #{inspect(compact)}")

    case compact do
      {:e, types} ->
        assert "Elixir.ArgumentError" in types

      :u ->
        flunk("Function shows as unknown - lambda effect not propagated")

      other ->
        flunk("Expected exception effect, got: #{inspect(other)}")
    end
  end

  test "filter_with_lambda_raising from edge cases - with custom exception" do
    source = """
    defmodule Support.ExceptionEdgeCasesTest do
      defmodule DomainError do
        defexception [:message, :domain]
      end

      def filter_with_lambda_raising(list) do
        Enum.filter(list, fn item ->
          if item < 0 do
            raise DomainError, message: "Negative numbers not allowed", domain: "positive"
          else
            item > 5
          end
        end)
      end
    end
    """

    {:ok, ast} = Code.string_to_quoted(source)
    {:ok, result} = ASTWalker.analyze_ast(ast)

    func = result.functions[{Support.ExceptionEdgeCasesTest, :filter_with_lambda_raising, 1}]
    assert func != nil, "Function should be found"

    compact = Core.to_compact_effect(func.effect)

    IO.puts("\nCustom exception in filter:")
    IO.puts("  Effect: #{inspect(func.effect, pretty: true)}")
    IO.puts("  Compact: #{inspect(compact)}")
    IO.puts("  Calls: #{inspect(func.calls)}")

    # Check if DomainError.exception/1 is being called
    domain_error_exception_call =
      Enum.any?(func.calls, fn
        {Support.ExceptionEdgeCasesTest.DomainError, :exception, 1} -> true
        _ -> false
      end)

    IO.puts("  DomainError.exception/1 called: #{domain_error_exception_call}")

    # Detailed analysis of what's in the effect
    IO.puts("\n  Analyzing effect components:")
    case func.effect do
      {:effect_row, first, rest} ->
        IO.puts("    First label: #{inspect(first)}")
        IO.puts("    Rest: #{inspect(rest, pretty: true)}")

      other ->
        IO.puts("    Single effect: #{inspect(other)}")
    end

    case compact do
      {:e, _types} ->
        IO.puts("  ✓ Exception effect detected (may be unknown type due to nested module)")

      :u ->
        IO.puts("  ✗ Unknown effect - checking why...")
        IO.puts("  The :unknown is from DomainError.exception/1 not being in the registry")

      other ->
        IO.puts("  ? Unexpected: #{inspect(other)}")
    end
  end
end
