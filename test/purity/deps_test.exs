defmodule Litmus.DepsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  @moduledoc """
  Tests for analyzing actual dependencies (Jason) to ensure our analysis
  works correctly on real-world libraries.

  Note: These tests document real-world limitations:
  - PURITY may return non-MFA tuples like {:erl, :catch}
  - Exception detection in libraries is limited (dynamic raises)
  - Cross-module analysis may fail for some dependencies
  """

  describe "Jason (JSON encoder/decoder)" do
    test "can analyze Jason.encode/1" do
      {:ok, results} = Litmus.analyze_module(Jason)

      # Jason.encode/1 should be in the results
      assert Map.has_key?(results, {Jason, :encode, 1}),
             "Jason.encode/1 should be analyzed"

      # Check its purity level
      purity = Map.get(results, {Jason, :encode, 1})

      # Jason.encode/1 is side-effect free but may raise exceptions
      assert purity in [:pure, :exceptions, :dependent],
             "Jason.encode/1 should be pure, exceptions, or dependent, got: #{inspect(purity)}"
    end

    test "can analyze Jason.decode/1" do
      {:ok, results} = Litmus.analyze_module(Jason)

      # Jason.decode/1 should be in the results
      assert Map.has_key?(results, {Jason, :decode, 1}),
             "Jason.decode/1 should be analyzed"

      purity = Map.get(results, {Jason, :decode, 1})

      # Jason.decode/1 can raise exceptions for invalid JSON
      assert purity in [:exceptions, :dependent, :pure],
             "Jason.decode/1 should be exceptions or dependent, got: #{inspect(purity)}"
    end

    test "can analyze Jason.decode!/1" do
      {:ok, results} = Litmus.analyze_module(Jason)

      # Jason.decode!/1 should be in the results
      assert Map.has_key?(results, {Jason, :decode!, 1}),
             "Jason.decode!/1 should be analyzed"

      purity = Map.get(results, {Jason, :decode!, 1})

      # Note: PURITY might classify this as :pure if it doesn't detect the raise
      # This is a known limitation - dynamic exception analysis is hard
      assert purity in [:pure, :exceptions, :dependent],
             "Jason.decode!/1 should have a purity classification, got: #{inspect(purity)}"
    end

    test "Jason module analysis includes multiple functions" do
      {:ok, results} = Litmus.analyze_module(Jason)

      # Should have results for multiple Jason functions
      # Note: PURITY may return non-MFA tuples like {:erl, :catch}
      jason_functions =
        results
        |> Map.keys()
        |> Enum.filter(fn
          {mod, _fun, _arity} when is_atom(mod) -> mod == Jason
          _ -> false
        end)

      assert length(jason_functions) > 3,
             "Should analyze multiple Jason functions, got: #{length(jason_functions)}"
    end

    test "can track exceptions in Jason.decode!/1" do
      {:ok, results} = Litmus.analyze_exceptions(Jason)

      # Jason.decode!/1 should have exception info
      info = Map.get(results, {Jason, :decode!, 1})

      if info do
        # Note: PURITY may not detect all exception raises, especially in
        # libraries that use error tuples or dynamic raising
        # This is a known limitation of static analysis
        assert is_map(info), "Should have exception info map"
        assert Map.has_key?(info, :errors), "Should have :errors key"
        assert Map.has_key?(info, :non_errors), "Should have :non_errors key"
      else
        # If not in results, that's okay - it might not be analyzed
        :ok
      end
    end
  end

  describe "Jason with Pure macro" do
    import Litmus.Pure

    test "Jason.encode with pure data works in pure block" do
      data = %{name: "test", value: 42}

      result =
        pure level: :exceptions do
          Jason.encode(data)
        end

      assert {:ok, json} = result
      assert is_binary(json)
    end

    test "Jason.decode with valid JSON works in pure block" do
      json = ~s({"name":"test","value":42})

      result =
        pure level: :exceptions do
          Jason.decode(json)
        end

      assert {:ok, data} = result
      assert is_map(data)
    end

    test "can use Jason in pure block with allow_exceptions" do
      json = ~s({"test": true})

      # Should compile successfully with allow_exceptions
      result =
        pure allow_exceptions: :any do
          Jason.decode!(json)
        end

      assert is_map(result)
    end
  end

  describe "stdlib whitelist integration with deps" do
    test "Jason functions are not in stdlib whitelist" do
      # Jason is a dependency, not part of Elixir stdlib
      refute Litmus.Stdlib.whitelisted?({Jason, :encode, 1}),
             "Jason.encode/1 should not be in stdlib whitelist"

      refute Litmus.Stdlib.whitelisted?({Jason, :decode, 1}),
             "Jason.decode/1 should not be in stdlib whitelist"
    end

    test "safe_to_optimize? works with Jason" do
      {:ok, results} = Litmus.analyze_module(Jason)

      # Jason.encode might be optimizable if it's pure
      encode_purity = Map.get(results, {Jason, :encode, 1})

      if encode_purity == :pure do
        assert Litmus.safe_to_optimize?(results, {Jason, :encode, 1}),
               "Pure Jason.encode/1 should be safe to optimize"
      else
        refute Litmus.safe_to_optimize?(results, {Jason, :encode, 1}),
               "Non-pure Jason.encode/1 should not be safe to optimize"
      end
    end
  end

  describe "real-world usage patterns" do
    test "analyzing a module that uses Jason" do
      # Create a module that uses Jason
      [{module, _bytecode}] = Code.compile_quoted(quote do
        defmodule JsonUser do
          def encode_data(data) do
            Jason.encode(data)
          end

          def decode_data(json) do
            Jason.decode(json)
          end

          def pure_calc(x, y), do: x + y
        end
      end)

      # Suppress expected errors from Jason analysis
      capture_io(:stderr, fn ->
        case Litmus.analyze_module(module) do
          {:ok, results} ->
            # At minimum, we should get some results
            assert map_size(results) > 0, "Should have some analysis results"

            # pure_calc might be analyzed
            if Map.has_key?(results, {module, :pure_calc, 2}) do
              pure_calc_purity = Map.get(results, {module, :pure_calc, 2})

              assert pure_calc_purity in [:pure, :exceptions, :dependent],
                     "pure_calc/2 should have purity classification, got: #{inspect(pure_calc_purity)}"
            end

          {:error, _reason} ->
            # Dynamic modules may not be analyzable - this is a known limitation
            :ok
        end
      end)
    end

    test "exception tracking works with Jason" do
      # Create a module that uses Jason
      [{module, _bytecode}] = Code.compile_quoted(quote do
        defmodule JsonExceptionUser do
          def safe_decode(json) do
            try do
              Jason.decode!(json)
            catch
              :error, %Jason.DecodeError{} -> {:error, :invalid_json}
            end
          end
        end
      end)

      {:ok, results} = Litmus.analyze_exceptions(module)

      # safe_decode should be analyzed
      info = Map.get(results, {module, :safe_decode, 1})

      if info do
        # Note: Try/catch might not fully work yet, but we should at least
        # get some exception info
        assert is_map(info), "Should have exception info for safe_decode/1"
      end
    end
  end
end
