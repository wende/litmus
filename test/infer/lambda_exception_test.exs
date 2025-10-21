defmodule LambdaExceptionTest do
  use ExUnit.Case
  alias Litmus.Analyzer.ASTWalker
  alias Litmus.Types.Core

  @moduletag :lambda_exception_debug

  test "lambda with if and raise has exception in body effect" do
    ast =
      quote do
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
      end

    {:ok, result} = ASTWalker.analyze_ast(ast)

    func = result.functions[{TestModule, :lambda_with_if_raise, 0}]
    assert func != nil, "Function should be found"

    # The function returns a lambda, so outer effect should be empty/pure
    compact = Core.to_compact_effect(func.effect)
    assert compact == :p, "Function returning lambda should be pure, got: #{inspect(compact)}"
  end

  test "Enum.filter with lambda containing raise propagates exception" do
    ast =
      quote do
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
      end

    {:ok, result} = ASTWalker.analyze_ast(ast)

    func = result.functions[{TestModule, :filter_with_raise, 1}]
    assert func != nil, "Function should be found"

    compact = Core.to_compact_effect(func.effect)

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
    ast =
      quote do
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
      end

    {:ok, result} = ASTWalker.analyze_ast(ast)

    func = result.functions[{TestModule, :map_with_raise, 1}]
    assert func != nil, "Function should be found"

    compact = Core.to_compact_effect(func.effect)

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
    ast =
      quote do
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
      end

    {:ok, result} = ASTWalker.analyze_ast(ast)

    func = result.functions[{Support.ExceptionEdgeCasesTest, :filter_with_lambda_raising, 1}]
    assert func != nil, "Function should be found"

    compact = Core.to_compact_effect(func.effect)

    # Should detect exception type from raised custom exception
    case compact do
      {:e, _types} ->
        # Exception effect detected
        :ok

      :u ->
        flunk("Expected exception effect, got unknown")

      other ->
        flunk("Expected exception effect, got: #{inspect(other)}")
    end
  end
end
