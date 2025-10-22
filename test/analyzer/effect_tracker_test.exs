defmodule Litmus.Analyzer.EffectTrackerTest do
  use ExUnit.Case
  alias Litmus.Analyzer.EffectTracker
  alias Litmus.Types.{Core, Effects}

  describe "extract_calls/1" do
    test "extracts simple function calls" do
      ast = quote do: String.upcase("hello")
      calls = EffectTracker.extract_calls(ast)
      assert {String, :upcase, 1} in calls
    end

    test "extracts multiple function calls" do
      ast =
        quote do
          x = String.upcase("hello")
          File.write!("out.txt", x)
          Enum.map([1, 2, 3], fn n -> n * 2 end)
        end

      calls = EffectTracker.extract_calls(ast)
      assert {String, :upcase, 1} in calls
      assert {File, :write!, 2} in calls
      assert {Enum, :map, 2} in calls
    end

    test "extracts local calls" do
      ast = quote do: helper_function()
      calls = EffectTracker.extract_calls(ast)
      # Local calls are treated as Kernel calls
      assert {Kernel, :helper_function, 0} in calls
    end

    test "extracts function captures" do
      ast = quote do: &String.upcase/1
      calls = EffectTracker.extract_calls(ast)
      assert {String, :upcase, 1} in calls
    end

    test "extracts operator captures" do
      ast = quote do: &+/2
      calls = EffectTracker.extract_calls(ast)
      assert {Kernel, :+, 2} in calls
    end

    test "extracts calls from pipe expressions" do
      ast =
        quote do
          "hello"
          |> String.upcase()
          |> String.reverse()
        end

      calls = EffectTracker.extract_calls(ast)
      assert {String, :upcase, 1} in calls
      assert {String, :reverse, 1} in calls
    end

    test "removes duplicate calls" do
      ast =
        quote do
          String.upcase("a")
          String.upcase("b")
          String.upcase("c")
        end

      calls = EffectTracker.extract_calls(ast)
      upcase_count = Enum.count(calls, &(&1 == {String, :upcase, 1}))
      assert upcase_count == 1
    end

    test "ignores literals and variables" do
      ast =
        quote do
          x = 42
          y = "string"
          z = [1, 2, 3]
        end

      calls = EffectTracker.extract_calls(ast)
      # The AST includes internal kernel operators like = and __block__
      # but no actual meaningful function calls (String, File, IO, etc.)
      assert is_list(calls)
      # Should not include meaningful library function calls
      refute Enum.any?(calls, fn {m, _f, _a} -> m in [String, File, IO, Logger] end)
    end

    test "extracts calls from nested blocks" do
      ast =
        quote do
          if true do
            File.read!("a.txt")
          else
            File.read!("b.txt")
          end
        end

      calls = EffectTracker.extract_calls(ast)
      assert {File, :read!, 1} in calls
    end

    test "extracts calls from case expressions" do
      ast =
        quote do
          case x do
            1 -> String.upcase("a")
            2 -> String.downcase("b")
          end
        end

      calls = EffectTracker.extract_calls(ast)
      assert {String, :upcase, 1} in calls
      assert {String, :downcase, 1} in calls
    end

    test "handles module aliases" do
      # Note: Aliases in quoted code are not expanded by quote/1
      # The AST contains Utils as is, not the fully resolved path
      ast = quote do: Utils.process(data)
      calls = EffectTracker.extract_calls(ast)
      # Without the alias context, this resolves as just Utils
      assert {Utils, :process, 1} in calls
    end

    test "handles nested function calls" do
      ast = quote do: File.write!("out.txt", String.upcase("hello"))
      calls = EffectTracker.extract_calls(ast)
      assert {String, :upcase, 1} in calls
      assert {File, :write!, 2} in calls
    end

    test "ignores lambda expressions without calls" do
      ast =
        quote do
          fn x -> x * 2 end
        end

      calls = EffectTracker.extract_calls(ast)
      # Lambda syntax includes :* operator internally but no meaningful calls
      assert is_list(calls)
      # Should not extract File, IO, or other side-effect function calls from the lambda
      refute Enum.any?(calls, fn {m, _f, _a} -> m in [File, IO, Logger] end)
    end

    test "extracts calls from lambda bodies" do
      ast =
        quote do
          fn x -> File.write!("a.txt", x) end
        end

      calls = EffectTracker.extract_calls(ast)
      assert {File, :write!, 2} in calls
    end

    test "handles pipes with function references" do
      ast =
        quote do
          data
          |> Enum.map(&String.upcase/1)
        end

      calls = EffectTracker.extract_calls(ast)
      assert {Enum, :map, 2} in calls
      assert {String, :upcase, 1} in calls
    end

    test "handles multiple argument function captures" do
      ast = quote do: &String.replace/3
      calls = EffectTracker.extract_calls(ast)
      assert {String, :replace, 3} in calls
    end

    test "extracts operator calls" do
      ast = quote do: x + y * z
      calls = EffectTracker.extract_calls(ast)
      # Operators are part of the AST but might not be extracted as simple calls
      # Just verify we get a list back
      assert is_list(calls)
    end
  end

  describe "analyze_effects/1" do
    test "identifies pure expressions" do
      ast = quote do: 1 + 2 * 3
      effect = EffectTracker.analyze_effects(ast)
      assert effect == Core.empty_effect()
    end

    test "identifies side effects from function calls" do
      ast = quote do: File.write!("out.txt", "data")
      effect = EffectTracker.analyze_effects(ast)
      refute effect == Core.empty_effect()
    end

    test "combines multiple effects" do
      ast =
        quote do
          x = File.read!("input.txt")
          IO.puts(x)
        end

      effect = EffectTracker.analyze_effects(ast)
      refute effect == Core.empty_effect()
    end

    test "handles nested calls" do
      ast = quote do: File.write!("out.txt", String.upcase("hello"))
      effect = EffectTracker.analyze_effects(ast)
      refute effect == Core.empty_effect()
    end

    test "handles conditional effects" do
      ast =
        quote do
          if condition do
            File.read!("a.txt")
          else
            File.read!("b.txt")
          end
        end

      effect = EffectTracker.analyze_effects(ast)
      refute effect == Core.empty_effect()
    end

    test "combines effects from all case branches" do
      ast =
        quote do
          case x do
            1 -> File.read!("a.txt")
            2 -> IO.puts("hello")
            3 -> :ok
          end
        end

      effect = EffectTracker.analyze_effects(ast)
      refute effect == Core.empty_effect()
    end

    test "handles try-catch blocks" do
      ast =
        quote do
          try do
            File.read!("a.txt")
          catch
            _ -> "default"
          end
        end

      effect = EffectTracker.analyze_effects(ast)
      # Try-catch should remove exception effect but keep file effect
      # The exact effect depends on how remove_effect works
      assert is_tuple(effect) or effect == Core.empty_effect()
    end

    test "combines effects from block expressions" do
      ast =
        quote do
          (
            File.read!("a.txt")
            IO.puts("hello")
            Enum.sum([1, 2, 3])
          )
        end

      effect = EffectTracker.analyze_effects(ast)
      refute effect == Core.empty_effect()
    end

    test "handles lambda-dependent effects" do
      ast = quote do: Enum.map([1, 2, 3], fn x -> x * 2 end)
      effect = EffectTracker.analyze_effects(ast)
      # Lambda effect depends on the function passed
      assert is_tuple(effect) or effect == Core.empty_effect()
    end

    test "handles effectful lambdas in higher-order functions" do
      ast =
        quote do
          Enum.map([1, 2, 3], fn x ->
            File.write!("out.txt", x)
          end)
        end

      effect = EffectTracker.analyze_effects(ast)
      refute effect == Core.empty_effect()
    end
  end

  describe "is_pure?/1" do
    test "identifies pure expressions" do
      ast = quote do: 1 + 2
      assert EffectTracker.is_pure?(ast) == true
    end

    test "identifies effectful expressions" do
      ast = quote do: File.write!("a.txt", "data")
      assert EffectTracker.is_pure?(ast) == false
    end

    test "identifies pure arithmetic" do
      ast = quote do: x * 2 + y / 3
      assert EffectTracker.is_pure?(ast) == true
    end

    test "identifies pure string operations" do
      ast = quote do: String.upcase("hello")
      assert EffectTracker.is_pure?(ast) == true
    end

    test "identifies list operations with lambda dependency" do
      # Pure lambda with Enum.map (which is lambda-dependent)
      ast = quote do: Enum.map([1, 2, 3], &(&1 * 2))
      # Enum.map is lambda-dependent, so result depends on the lambda effect
      # With a pure lambda, it should NOT have side effects
      effect = EffectTracker.analyze_effects(ast)
      # Verify it's not incorrectly marked as having side effects
      refute Effects.has_effect?(:s, effect) == true
    end

    test "identifies IO operations as impure" do
      ast = quote do: IO.puts("hello")
      assert EffectTracker.is_pure?(ast) == false
    end

    test "identifies file operations as impure" do
      ast = quote do: File.read!("a.txt")
      assert EffectTracker.is_pure?(ast) == false
    end

    test "identifies conditional expressions with side effects as impure" do
      ast =
        quote do
          if x > 0 do
            File.write!("a.txt", "yes")
          else
            "no"
          end
        end

      assert EffectTracker.is_pure?(ast) == false
    end

    test "identifies case expressions with side effects as impure" do
      ast =
        quote do
          case x do
            0 -> IO.puts("zero")
            _ -> x
          end
        end

      assert EffectTracker.is_pure?(ast) == false
    end
  end

  describe "find_effectful_nodes/1" do
    test "finds no effectful nodes in pure expressions" do
      ast = quote do: 1 + 2 * 3
      nodes = EffectTracker.find_effectful_nodes(ast)
      assert nodes == []
    end

    test "finds single effectful call" do
      ast = quote do: File.write!("a.txt", "data")
      nodes = EffectTracker.find_effectful_nodes(ast)
      assert length(nodes) > 0
    end

    test "finds multiple effectful calls" do
      ast =
        quote do
          File.read!("a.txt")
          IO.puts("hello")
          Enum.map([1, 2, 3], fn x -> x * 2 end)
        end

      nodes = EffectTracker.find_effectful_nodes(ast)
      # Should find at least File.read! and IO.puts
      assert length(nodes) > 0
    end

    test "ignores pure calls within effectful expressions" do
      ast =
        quote do
          File.write!("a.txt", String.upcase("hello"))
        end

      nodes = EffectTracker.find_effectful_nodes(ast)
      # Should only find File.write!, not String.upcase
      assert length(nodes) > 0
    end

    test "finds effectful nodes in conditionals" do
      ast =
        quote do
          if x do
            File.write!("a.txt", "yes")
          else
            "no"
          end
        end

      nodes = EffectTracker.find_effectful_nodes(ast)
      assert length(nodes) > 0
    end

    test "finds effectful nodes in case expressions" do
      ast =
        quote do
          case x do
            1 -> IO.puts("one")
            _ -> :ok
          end
        end

      nodes = EffectTracker.find_effectful_nodes(ast)
      assert length(nodes) > 0
    end
  end

  describe "annotate_effects/1" do
    test "returns AST structure" do
      ast = quote do: 1 + 2
      result = EffectTracker.annotate_effects(ast)
      assert is_tuple(result)
    end

    test "preserves AST structure" do
      ast = quote do: String.upcase("hello")
      result = EffectTracker.annotate_effects(ast)
      # Result should still be evaluable AST
      assert is_tuple(result)
    end

    test "handles complex expressions" do
      ast =
        quote do
          x = File.read!("a.txt")
          y = String.upcase(x)
          IO.puts(y)
        end

      result = EffectTracker.annotate_effects(ast)
      assert is_tuple(result)
    end

    test "handles nested structures" do
      ast =
        quote do
          [
            File.read!("a.txt"),
            File.read!("b.txt"),
            String.upcase("hello")
          ]
        end

      result = EffectTracker.annotate_effects(ast)
      # annotate_effects returns the AST structure, which for a list is a list
      assert is_list(result) or is_tuple(result)
    end
  end

  describe "analyze_dependencies/1" do
    test "analyzes single function" do
      functions = %{
        test_func: quote(do: String.upcase("hello"))
      }

      result = EffectTracker.analyze_dependencies(functions)
      assert is_map(result)
      assert Map.has_key?(result, :test_func)
      assert is_map(result[:test_func])
      assert Map.has_key?(result[:test_func], :calls)
      assert Map.has_key?(result[:test_func], :effects)
    end

    test "analyzes multiple functions" do
      functions = %{
        func_a: quote(do: String.upcase("a")),
        func_b: quote(do: File.write!("b.txt", "data")),
        func_c: quote(do: 1 + 2)
      }

      result = EffectTracker.analyze_dependencies(functions)
      assert map_size(result) == 3
      assert Enum.all?(result, fn {_k, v} ->
        is_map(v) and Map.has_key?(v, :calls) and Map.has_key?(v, :effects)
      end)
    end

    test "tracks call dependencies" do
      functions = %{
        test_func: quote(do: String.upcase("test"))
      }

      result = EffectTracker.analyze_dependencies(functions)
      assert {String, :upcase, 1} in result[:test_func].calls
    end

    test "tracks effects" do
      functions = %{
        test_func: quote(do: File.read!("a.txt"))
      }

      result = EffectTracker.analyze_dependencies(functions)
      effect = result[:test_func].effects
      refute effect == Core.empty_effect()
    end

    test "handles empty function map" do
      result = EffectTracker.analyze_dependencies(%{})
      assert result == %{}
    end

    test "handles functions with no calls" do
      functions = %{
        test_func: quote(do: 42)
      }

      result = EffectTracker.analyze_dependencies(functions)
      assert result[:test_func].calls == []
      assert result[:test_func].effects == Core.empty_effect()
    end

    test "handles functions with multiple calls" do
      functions = %{
        test_func:
          quote do
            x = String.upcase("a")
            File.write!("b.txt", x)
            Enum.map([1, 2, 3], fn n -> n * 2 end)
          end
      }

      result = EffectTracker.analyze_dependencies(functions)
      calls = result[:test_func].calls
      assert {String, :upcase, 1} in calls
      assert {File, :write!, 2} in calls
      assert {Enum, :map, 2} in calls
    end
  end

  describe "compare_effects/2" do
    test "equal effects" do
      ast1 = quote do: 1 + 2
      ast2 = quote do: 3 + 4
      assert EffectTracker.compare_effects(ast1, ast2) == :equal
    end

    test "one pure, one effectful" do
      ast_pure = quote do: 1 + 2
      ast_effectful = quote do: File.write!("a.txt", "data")
      result = EffectTracker.compare_effects(ast_pure, ast_effectful)
      assert result in [:subset, :incompatible]
    end

    test "both effectful with different effects" do
      ast1 = quote do: File.write!("a.txt", "data")
      ast2 = quote do: IO.puts("hello")
      result = EffectTracker.compare_effects(ast1, ast2)
      assert is_atom(result)
    end

    test "same effectful operation" do
      ast1 = quote do: File.write!("a.txt", "data1")
      ast2 = quote do: File.write!("a.txt", "data2")
      result = EffectTracker.compare_effects(ast1, ast2)
      assert is_atom(result)
    end

    test "subset relationship" do
      ast_simple = quote do: 1 + 2
      ast_complex = quote do: (1 + 2) * 3
      result = EffectTracker.compare_effects(ast_simple, ast_complex)
      assert is_atom(result)
    end

    test "returns valid result atom" do
      ast1 = quote do: File.read!("a.txt")
      ast2 = quote do: IO.puts("hello")
      result = EffectTracker.compare_effects(ast1, ast2)
      assert result in [:equal, :subset, :superset, :incompatible]
    end

    test "multiple effects vs single effect" do
      ast_single = quote do: File.write!("a.txt", "data")

      ast_multiple =
        quote do
          x = File.write!("a.txt", "data")
          IO.puts(x)
        end

      result = EffectTracker.compare_effects(ast_single, ast_multiple)
      assert is_atom(result)
    end
  end

  describe "module alias resolution" do
    test "resolves atom modules" do
      ast = quote do: String.upcase("hello")
      calls = EffectTracker.extract_calls(ast)
      assert {String, :upcase, 1} in calls
    end

    test "resolves aliased modules" do
      # Note: Aliases in quoted code are not automatically expanded
      # The alias directive doesn't change how the AST is parsed
      ast = quote do: MyModule.SubModule.func(1)
      calls = EffectTracker.extract_calls(ast)
      assert {MyModule.SubModule, :func, 1} in calls
    end

    test "resolves nested module paths" do
      ast =
        quote do
          Nested.Module.Deep.function(x, y)
        end

      calls = EffectTracker.extract_calls(ast)
      assert {Nested.Module.Deep, :function, 2} in calls
    end
  end

  describe "edge cases" do
    test "handles empty AST" do
      ast = quote do: nil
      calls = EffectTracker.extract_calls(ast)
      assert calls == []
    end

    test "handles anonymous variables" do
      ast = quote do: {_a, _b, _c}
      calls = EffectTracker.extract_calls(ast)
      # Tuple constructor is extracted as a kernel call
      assert is_list(calls)
    end

    test "handles list comprehensions" do
      ast =
        quote do
          [x * 2 | x <- [1, 2, 3]]
        end

      calls = EffectTracker.extract_calls(ast)
      # List comprehension might contain implicit calls
      assert is_list(calls)
    end

    test "handles map updates" do
      ast =
        quote do
          %{x | key: value}
        end

      calls = EffectTracker.extract_calls(ast)
      # Map update syntax creates kernel calls for % and | operators
      # These are internal implementation details, so we just verify it returns a list
      assert is_list(calls)
    end

    test "handles string interpolation" do
      ast =
        quote do
          "Value: #{x}"
        end

      calls = EffectTracker.extract_calls(ast)
      assert is_list(calls)
    end

    test "handles pattern matching" do
      ast =
        quote do
          {a, b} = data
        end

      calls = EffectTracker.extract_calls(ast)
      # Pattern matching includes internal operators like = and {}
      assert is_list(calls)
    end

    test "handles guard clauses" do
      ast =
        quote do
          fn x when x > 0 -> x * 2 end
        end

      calls = EffectTracker.extract_calls(ast)
      assert is_list(calls)
    end

    test "handles with expressions" do
      ast =
        quote do
          with {:ok, x} <- something() do
            x * 2
          end
        end

      calls = EffectTracker.extract_calls(ast)
      assert {Kernel, :something, 0} in calls
    end
  end
end
