defmodule Test.AnalysisHelpers do
  @moduledoc """
  Shared helper functions for AST analysis and effect testing across test files.

  This module provides common functionality to reduce code duplication in tests:
  - AST cleaning and analysis
  - Effect assertion helpers
  - Common test patterns
  """

  alias Litmus.Analyzer.ASTWalker
  alias Litmus.Types.{Core, Effects}

  @doc """
  Analyzes quoted AST by cleaning test context variables and running analysis.

  ## Parameters
  - ast: The quoted AST to analyze

  ## Returns
  - {:ok, result} with analysis result or error tuple
  """
  def analyze_ast(ast) do
    # Replace test context variable references with fresh vars
    clean_ast =
      Macro.prewalk(ast, fn
        # Replace variable references from test context with fresh vars
        {var, meta, context} when is_atom(var) and is_atom(context) ->
          {var, meta, nil}

        node ->
          node
      end)

    # Analyze the cleaned AST
    ASTWalker.analyze_ast(clean_ast)
  end

  @doc """
  Analyzes source code string by parsing to AST and analyzing.

  ## Parameters
  - source: String containing Elixir source code

  ## Returns
  - {:ok, result} with analysis result or error tuple
  """
  def analyze_source(source) do
    with {:ok, ast} <- Code.string_to_quoted(source) do
      analyze_ast(ast)
    end
  end

  @doc """
  Creates a test module with the given function definitions.

  ## Parameters
  - module_name: Name of the test module (atom)
  - functions: List of function definition strings

  ## Returns
  - Quoted AST for the module
  """
  def create_test_module(module_name, functions) when is_list(functions) do
    function_code = Enum.join(functions, "\n\n  ")

    source = """
    defmodule #{module_name} do
      #{function_code}
    end
    """

    {:ok, ast} = Code.string_to_quoted(source)
    ast
  end

  def create_test_module(module_name, function_def) do
    create_test_module(module_name, [function_def])
  end

  @doc """
  Extracts function analysis from result for the given MFA.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple

  ## Returns
  - Function analysis struct or nil if not found
  """
  def get_function_analysis(result, mfa) do
    result.functions[mfa]
  end

  @doc """
  Gets the effect type for a function in compact notation.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple

  ## Returns
  - Compact effect type (atom or tuple)
  """
  def get_compact_effect(result, mfa) do
    func = get_function_analysis(result, mfa)
    if func, do: Core.to_compact_effect(func.effect)
  end

  @doc """
  Checks if a function has a pure effect.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple

  ## Returns
  - boolean indicating if effect is pure
  """
  def function_pure?(result, mfa) do
    func = get_function_analysis(result, mfa)
    if func, do: Effects.is_pure?(func.effect)
  end

  @doc """
  Checks if a function has side effects.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple

  ## Returns
  - boolean indicating if effect has side effects
  """
  def function_has_side_effects?(result, mfa) do
    func = get_function_analysis(result, mfa)
    func && Effects.has_effect?(:s, func.effect) == true
  end

  @doc """
  Checks if a function has exception effects.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple

  ## Returns
  - boolean indicating if effect has exceptions
  """
  def function_has_exceptions?(result, mfa) do
    func = get_function_analysis(result, mfa)
    func && Effects.has_effect?(:exn, func.effect) == true
  end

  @doc """
  Checks if a function is lambda-dependent.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple

  ## Returns
  - boolean indicating if effect is lambda-dependent
  """
  def function_lambda_dependent?(result, mfa) do
    effect = get_compact_effect(result, mfa)
    effect == :l
  end

  @doc """
  Checks if a function has unknown effects.

  ## Parameters
  - result: Analysis result from ASTWalker
  - mfa: {module, function, arity} tuple

  ## Returns
  - boolean indicating if effect is unknown
  """
  def function_unknown?(result, mfa) do
    effect = get_compact_effect(result, mfa)
    effect == :u
  end

  @doc """
  Gets all function MFAs from analysis result.

  ## Parameters
  - result: Analysis result from ASTWalker

  ## Returns
  - List of {module, function, arity} tuples
  """
  def list_functions(result) do
    Map.keys(result.functions)
  end

  @doc """
  Filters functions by effect type.

  ## Parameters
  - result: Analysis result from ASTWalker
  - effect_type: Atom representing effect type (:p, :s, :l, :e, :u, :d, :n)

  ## Returns
  - List of MFAs with the specified effect type
  """
  def filter_by_effect_type(result, effect_type) do
    result.functions
    |> Enum.filter(fn {_mfa, func} ->
      Core.to_compact_effect(func.effect) == effect_type
    end)
    |> Enum.map(&elem(&1, 0))
  end

  @doc """
  Checks that analysis completes successfully and returns functions.

  ## Parameters
  - ast_or_source: Either quoted AST or source string

  ## Returns
  - Analysis result for further assertions

  ## Raises
  - ExUnit.AssertionError if analysis fails
  """
  def assert_analysis_completes(ast_or_source) do
    result =
      case ast_or_source do
        string when is_binary(string) -> analyze_source(string)
        ast -> analyze_ast(ast)
      end

    case result do
      {:ok, result} when is_map(result.functions) ->
        result

      {:ok, result} ->
        raise ExUnit.AssertionError, "Expected functions map, got: #{inspect(result)}"

      {:error, reason} ->
        raise ExUnit.AssertionError, "Analysis failed: #{inspect(reason)}"
    end
  end

  @doc """
  Creates a lambda function AST with the given pattern and body.

  ## Parameters
  - pattern: Pattern string (e.g., "{a, b}")
  - body: Body expression string

  ## Returns
  - Quoted lambda AST
  """
  def create_lambda(pattern, body) do
    source = "fn #{pattern} -> #{body} end"
    {:ok, ast} = Code.string_to_quoted(source)
    ast
  end

  @doc """
  Creates a function call AST.

  ## Parameters
  - module: Module name (atom)
  - function: Function name (atom)
  - args: List of argument expressions

  ## Returns
  - Quoted function call AST
  """
  def create_function_call(module, function, args) do
    args_ast =
      Enum.map(args, fn arg ->
        case Code.string_to_quoted("#{arg}") do
          {:ok, ast} -> ast
          _ -> arg
        end
      end)

    {{:., [], [{:__aliases__, [], [module]}, function]}, [], args_ast}
  end
end
