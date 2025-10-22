defmodule Test.Assertions do
  @moduledoc """
  Custom assertion helpers for effect testing to reduce duplication in test files.

  This module provides specialized assertions for:
  - Effect type checking
  - AST analysis results
  - Exception testing
  - Function analysis validation
  """

  alias Litmus.Types.{Core, Effects}
  alias Test.AnalysisHelpers

  # Import ExUnit assertions for use in this module
  import ExUnit.Assertions

  @doc """
  Asserts that an effect has side effects.

  ## Parameters
  - effect: The effect to check (in any format)

  ## Examples
      assert_side_effect({:s, ["IO.puts/1"]})
      assert_side_effect({:effect_row, {:s, _}, _})
  """
  def assert_side_effect(effect) do
    assert match?({:s, list} when is_list(list), effect) or
             match?({:effect_row, {:s, _}, _}, effect) or
             match?({:effect_row, _, {:s, _}}, effect),
           "Expected side effect, got: #{inspect(effect)}"
  end

  @doc """
  Asserts that an effect is pure.

  ## Parameters
  - effect: The effect to check (in any format)
  """
  def assert_pure_effect(effect) do
    assert Effects.is_pure?(effect),
           "Expected pure effect, got: #{inspect(effect)}"
  end

  @doc """
  Asserts that an effect has exceptions.

  ## Parameters
  - effect: The effect to check (in any format)
  - expected_types: Optional list of expected exception types
  """
  def assert_exception_effect(effect, expected_types \\ nil) do
    assert Effects.has_effect?(:exn, effect) == true,
           "Expected exception effect, got: #{inspect(effect)}"

    if expected_types do
      actual_types = Effects.extract_exception_types(effect)

      assert Enum.all?(expected_types, &(&1 in actual_types)),
             "Expected exception types #{inspect(expected_types)}, got: #{inspect(actual_types)}"
    end
  end

  @doc """
  Asserts that an effect is lambda-dependent.

  ## Parameters
  - effect: The effect to check (in any format)
  """
  def assert_lambda_dependent_effect(effect) do
    compact_effect = Core.to_compact_effect(effect)

    assert compact_effect == :l,
           "Expected lambda-dependent effect, got: #{inspect(compact_effect)}"
  end

  @doc """
  Asserts that an effect is unknown.

  ## Parameters
  - effect: The effect to check (in any format)
  """
  def assert_unknown_effect(effect) do
    compact_effect = Core.to_compact_effect(effect)

    assert compact_effect == :u,
           "Expected unknown effect, got: #{inspect(compact_effect)}"
  end

  @doc """
  Asserts that an effect is dependent (context-dependent).

  ## Parameters
  - effect: The effect to check (in any format)
  """
  def assert_dependent_effect(effect) do
    compact_effect = Core.to_compact_effect(effect)

    assert compact_effect == :d,
           "Expected dependent effect, got: #{inspect(compact_effect)}"
  end

  @doc """
  Asserts that an effect is NIF (native code).

  ## Parameters
  - effect: The effect to check (in any format)
  """
  def assert_nif_effect(effect) do
    compact_effect = Core.to_compact_effect(effect)

    assert compact_effect == :n,
           "Expected NIF effect, got: #{inspect(compact_effect)}"
  end

  @doc """
  Asserts that a function analysis has the expected effect type.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple
  - expected_type: Expected effect type atom (:p, :s, :l, :e, :u, :d, :n)
  """
  def assert_function_effect_type(result, mfa, expected_type) do
    actual_type = AnalysisHelpers.get_compact_effect(result, mfa)

    assert actual_type == expected_type,
           "Expected function {#{elem(mfa, 0)}, #{elem(mfa, 1)}, #{elem(mfa, 2)}} to have effect #{expected_type}, got #{actual_type}"
  end

  @doc """
  Asserts that a function analysis has side effects.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple
  """
  def assert_function_has_side_effects(result, mfa) do
    assert AnalysisHelpers.function_has_side_effects?(result, mfa),
           "Expected function {#{elem(mfa, 0)}, #{elem(mfa, 1)}, #{elem(mfa, 2)}} to have side effects"
  end

  @doc """
  Asserts that a function analysis is pure.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple
  """
  def assert_function_is_pure(result, mfa) do
    assert AnalysisHelpers.function_pure?(result, mfa),
           "Expected function {#{elem(mfa, 0)}, #{elem(mfa, 1)}, #{elem(mfa, 2)}} to be pure"
  end

  @doc """
  Asserts that a function analysis has exceptions.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple
  - expected_types: Optional list of expected exception types
  """
  def assert_function_has_exceptions(result, mfa, expected_types \\ nil) do
    assert AnalysisHelpers.function_has_exceptions?(result, mfa),
           "Expected function {#{elem(mfa, 0)}, #{elem(mfa, 1)}, #{elem(mfa, 2)}} to have exceptions"

    if expected_types do
      func = AnalysisHelpers.get_function_analysis(result, mfa)
      actual_types = Effects.extract_exception_types(func.effect)

      assert Enum.all?(expected_types, &(&1 in actual_types)),
             "Expected exception types #{inspect(expected_types)}, got: #{inspect(actual_types)}"
    end
  end

  @doc """
  Asserts that a function analysis is lambda-dependent.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple
  """
  def assert_function_is_lambda_dependent(result, mfa) do
    assert AnalysisHelpers.function_lambda_dependent?(result, mfa),
           "Expected function {#{elem(mfa, 0)}, #{elem(mfa, 1)}, #{elem(mfa, 2)}} to be lambda-dependent"
  end

  @doc """
  Asserts that a function analysis is unknown.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple
  """
  def assert_function_is_unknown(result, mfa) do
    assert AnalysisHelpers.function_unknown?(result, mfa),
           "Expected function {#{elem(mfa, 0)}, #{elem(mfa, 1)}, #{elem(mfa, 2)}} to be unknown"
  end

  @doc """
  Asserts that specific function calls are present in the analysis.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple
  - expected_calls: List of expected {module, function, arity} tuples
  """
  def assert_function_calls(result, mfa, expected_calls) do
    func = AnalysisHelpers.get_function_analysis(result, mfa)
    assert func != nil, "Function {#{elem(mfa, 0)}, #{elem(mfa, 1)}, #{elem(mfa, 2)}} not found"

    for expected_call <- expected_calls do
      assert expected_call in func.calls,
             "Expected call #{inspect(expected_call)} not found in function calls: #{inspect(func.calls)}"
    end
  end

  @doc """
  Asserts that a function has the expected visibility.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple
  - expected_visibility: :def or :defp
  """
  def assert_function_visibility(result, mfa, expected_visibility) do
    func = AnalysisHelpers.get_function_analysis(result, mfa)
    assert func != nil, "Function {#{elem(mfa, 0)}, #{elem(mfa, 1)}, #{elem(mfa, 2)}} not found"

    assert func.visibility == expected_visibility,
           "Expected visibility #{expected_visibility}, got #{func.visibility}"
  end

  @doc """
  Asserts that analysis completed successfully and contains expected functions.

  ## Parameters
  - ast_or_source: Either quoted AST or source string
  - expected_functions: List of expected {module, function, arity} tuples
  """
  def assert_analysis_with_functions(ast_or_source, expected_functions) do
    result = AnalysisHelpers.assert_analysis_completes(ast_or_source)

    for expected_mfa <- expected_functions do
      assert AnalysisHelpers.get_function_analysis(result, expected_mfa) != nil,
             "Expected function #{inspect(expected_mfa)} not found in analysis results"
    end

    result
  end

  @doc """
  Asserts that analysis has the expected number of functions.

  ## Parameters
  - ast_or_source: Either quoted AST or source string
  - expected_count: Expected number of functions
  """
  def assert_analysis_function_count(ast_or_source, expected_count) do
    result = AnalysisHelpers.assert_analysis_completes(ast_or_source)
    actual_count = map_size(result.functions)

    assert actual_count == expected_count,
           "Expected #{expected_count} functions, got #{actual_count}"

    result
  end

  @doc """
  Asserts that specific effect types are present in the analysis results.

  ## Parameters
  - result: Analysis result from ASTWalker
  - expected_counts: Map of effect types to expected counts
  """
  def assert_effect_type_counts(result, expected_counts) do
    actual_counts =
      result.functions
      |> Enum.group_by(fn {_mfa, func} -> Core.to_compact_effect(func.effect) end)
      |> Enum.map(fn {effect_type, funcs} -> {effect_type, length(funcs)} end)
      |> Map.new()

    for {effect_type, expected_count} <- expected_counts do
      actual_count = Map.get(actual_counts, effect_type, 0)

      assert actual_count == expected_count,
             "Expected #{expected_count} functions with effect #{effect_type}, got #{actual_count}"
    end
  end

  @doc """
  Asserts that an exception is raised when executing the given function.

  ## Parameters
  - func: Function to execute
  - expected_exception: Optional expected exception module
  - expected_message: Optional expected message pattern (regex or string)
  """
  def assert_raises(func, expected_exception \\ nil, expected_message \\ nil) do
    assert_raise expected_exception, expected_message, func
  end

  @doc """
  Asserts that a specific MFA has the expected effect type in the registry.

  ## Parameters
  - mfa: {module, function, arity} tuple
  - expected_type: Expected effect type
  """
  def assert_registry_effect_type(mfa, expected_type) do
    alias Litmus.Effects.Registry

    actual_type = Registry.effect_type(mfa)

    assert actual_type == expected_type,
           "Expected registry effect type #{expected_type} for #{inspect(mfa)}, got #{actual_type}"
  end

  @doc """
  Asserts that a specific MFA resolves to the expected leaf functions.

  ## Parameters
  - mfa: {module, function, arity} tuple
  - expected_modules: List of expected module names in the resolved leaves
  """
  def assert_resolves_to_modules(mfa, expected_modules) do
    alias Litmus.Effects.Registry

    {:ok, leaves} = Registry.resolve_to_leaves(mfa)
    actual_modules = Enum.map(leaves, &elem(&1, 0)) |> Enum.uniq()

    for expected_module <- expected_modules do
      assert expected_module in actual_modules,
             "Expected module #{expected_module} in resolved leaves for #{inspect(mfa)}, got: #{inspect(actual_modules)}"
    end
  end

  @doc """
  Asserts that JSON output is valid and contains expected structure.

  ## Parameters
  - json_string: JSON string to validate
  - expected_keys: List of expected top-level keys
  """
  def assert_valid_json(json_string, expected_keys \\ []) do
    assert {:ok, parsed} = Jason.decode(json_string),
           "Invalid JSON: #{json_string}"

    assert is_map(parsed),
           "Expected JSON to be an object, got: #{inspect(parsed)}"

    for key <- expected_keys do
      assert Map.has_key?(parsed, key),
             "Expected JSON to contain key '#{key}', got: #{inspect(Map.keys(parsed))}"
    end

    parsed
  end

  @doc """
  Asserts that output contains expected patterns.

  ## Parameters
  - output: String output to check
  - patterns: List of patterns (strings or regex) that should be present
  - exclude_patterns: List of patterns that should NOT be present
  """
  def assert_output_contains(output, patterns \\ [], exclude_patterns \\ []) do
    for pattern <- patterns do
      case pattern do
        regex when is_struct(regex, Regex) ->
          assert Regex.match?(regex, output),
                 "Expected output to match #{inspect(regex)}, got: #{output}"

        string ->
          assert output =~ string, "Expected output to contain '#{string}', got: #{output}"
      end
    end

    for pattern <- exclude_patterns do
      case pattern do
        regex when is_struct(regex, Regex) ->
          refute Regex.match?(regex, output),
                 "Expected output NOT to match #{inspect(regex)}, got: #{output}"

        string ->
          refute output =~ string, "Expected output NOT to contain '#{string}', got: #{output}"
      end
    end
  end
end
