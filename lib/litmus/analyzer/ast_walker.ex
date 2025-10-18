defmodule Litmus.Analyzer.ASTWalker do
  @moduledoc """
  AST walker for analyzing Elixir code and inferring types and effects.

  This module traverses Elixir AST and performs bidirectional type inference
  with effect tracking. It integrates with the existing effects system and
  provides comprehensive analysis of modules, functions, and expressions.
  """

  alias Litmus.Inference.{Bidirectional, Context}
  alias Litmus.Types.Core
  alias Litmus.Analyzer.EffectTracker

  @type analysis_result :: %{
    module: module(),
    functions: %{mfa() => function_analysis()},
    types: %{mfa() => Core.elixir_type()},
    effects: %{mfa() => Core.effect_type()},
    errors: list(analysis_error())
  }

  @type function_analysis :: %{
    type: Core.elixir_type(),
    effect: Core.effect_type(),
    params: list(Core.elixir_type()),
    return_type: Core.elixir_type(),
    calls: list(mfa()),
    line: non_neg_integer()
  }

  @type analysis_error :: %{
    type: :type_error | :effect_error | :unknown_function,
    message: String.t(),
    location: {module(), atom(), non_neg_integer()},
    details: map()
  }

  @doc """
  Analyzes a module from a .beam file by extracting its AST.

  ## Examples

      iex> analyze_file("_build/dev/lib/my_app/ebin/Elixir.MyModule.beam")
      {:ok, %{module: MyModule, functions: %{...}, ...}}
  """
  def analyze_file(path) when is_binary(path) do
    # Extract module name from beam file path
    # e.g., "Elixir.MyModule.beam" -> MyModule
    module_name =
      path
      |> Path.basename()
      |> String.replace_suffix(".beam", "")
      |> String.replace_prefix("Elixir.", "")
      |> String.to_atom()

    analyze_module(module_name)
  end

  @doc """
  Analyzes an already-parsed AST.
  """
  def analyze_ast(ast) do
    # Start the variable generator if not already started
    ensure_var_gen_started()

    case ast do
      {:defmodule, _, [module_name, [do: module_body]]} ->
        module = extract_module_name(module_name)
        analyze_module(module, module_body)

      _ ->
        {:error, :not_a_module}
    end
  end

  @doc """
  Analyzes a compiled module by decompiling to AST.
  """
  def analyze_module(module) when is_atom(module) do
    case fetch_module_ast(module) do
      {:ok, ast} ->
        analyze_ast(ast)

      {:error, reason} ->
        {:error, {:module_fetch_error, reason}}
    end
  end

  # Analyze module contents
  defp analyze_module(module_name, {:__block__, _, definitions}) do
    analyze_module(module_name, definitions)
  end

  defp analyze_module(module_name, definitions) when is_list(definitions) do
    # Initialize analysis result
    initial_result = %{
      module: module_name,
      functions: %{},
      types: %{},
      effects: %{},
      errors: []
    }

    # Create initial context with stdlib
    context = Context.with_stdlib()

    # Analyze each definition
    result = Enum.reduce(definitions, {initial_result, context}, fn def_ast, {acc, ctx} ->
      analyze_definition(def_ast, acc, ctx)
    end)

    case result do
      {final_result, _final_context} ->
        {:ok, final_result}

      error ->
        error
    end
  end

  defp analyze_module(module_name, single_def) do
    analyze_module(module_name, [single_def])
  end

  # Analyze individual definitions
  defp analyze_definition({:def, meta, [signature, [do: body]]}, result, context) do
    analyze_function(:def, meta, signature, body, result, context)
  end

  defp analyze_definition({:defp, meta, [signature, [do: body]]}, result, context) do
    analyze_function(:defp, meta, signature, body, result, context)
  end

  defp analyze_definition({:@, _, [{:spec, _, _spec}]}, result, context) do
    # TODO: Handle @spec annotations for better type inference
    {result, context}
  end

  defp analyze_definition({:@, _, [{:type, _, _type_def}]}, result, context) do
    # TODO: Handle @type definitions
    {result, context}
  end

  defp analyze_definition(_, result, context) do
    # Ignore other definitions (attributes, etc.)
    {result, context}
  end

  # Analyze function definition
  defp analyze_function(visibility, meta, signature, body, result, context) do
    line = Keyword.get(meta, :line, 0)

    case extract_function_info(signature) do
      {:ok, name, params} ->
        # Create MFA
        module = result.module
        arity = length(params)
        mfa = {module, name, arity}

        # Add parameters to context
        {param_types, param_context} = add_params_to_context(params, context)

        # Expand pipes in the body before analysis
        expanded_body = expand_pipes(body)

        # Analyze function body
        case Bidirectional.synthesize(expanded_body, param_context) do
          {:ok, body_type, body_effect, _subst} ->
            # Build function type
            fun_type = build_function_type(param_types, body_type, body_effect)

            # Track function calls in body
            calls = EffectTracker.extract_calls(body)

            # Create function analysis
            func_analysis = %{
              type: fun_type,
              effect: body_effect,
              params: param_types,
              return_type: body_type,
              calls: calls,
              line: line,
              visibility: visibility
            }

            # Update result
            updated_result = result
                             |> Map.update!(:functions, &Map.put(&1, mfa, func_analysis))
                             |> Map.update!(:types, &Map.put(&1, mfa, fun_type))
                             |> Map.update!(:effects, &Map.put(&1, mfa, body_effect))

            # Add function to context for recursive calls
            new_context = Context.add(context, name, fun_type)

            {updated_result, new_context}

          {:error, error} ->
            # Record error
            error_entry = %{
              type: :type_error,
              message: format_error(error),
              location: {module, name, line},
              details: %{error: error, params: params}
            }

            updated_result = Map.update!(result, :errors, &[error_entry | &1])
            {updated_result, context}
        end

      {:error, reason} ->
        # Record error
        error_entry = %{
          type: :unknown_function,
          message: "Failed to parse function signature: #{inspect(reason)}",
          location: {result.module, :unknown, line},
          details: %{signature: signature}
        }

        updated_result = Map.update!(result, :errors, &[error_entry | &1])
        {updated_result, context}
    end
  end

  # Extract function name and parameters
  defp extract_function_info({name, _, params}) when is_atom(name) and is_list(params) do
    {:ok, name, params}
  end

  # Zero-arity function (params is a context atom, not a list)
  defp extract_function_info({name, _, context}) when is_atom(name) and is_atom(context) do
    {:ok, name, []}
  end

  defp extract_function_info({:when, _, [{name, _, params}, _guard]})
       when is_atom(name) and is_list(params) do
    {:ok, name, params}
  end

  # Zero-arity function with guard
  defp extract_function_info({:when, _, [{name, _, context}, _guard]})
       when is_atom(name) and is_atom(context) do
    {:ok, name, []}
  end

  defp extract_function_info(_) do
    {:error, :invalid_signature}
  end

  # Add parameters to typing context
  defp add_params_to_context(params, context) do
    {param_types, new_context} = Enum.reduce(params, {[], context}, fn param, {types, ctx} ->
      case param do
        {name, _, nil} when is_atom(name) ->
          # Create fresh type variable for parameter
          param_type = Bidirectional.VarGen.fresh_type_var()
          {[param_type | types], Context.add(ctx, name, param_type)}

        _ ->
          # Complex pattern - use fresh variable
          param_type = Bidirectional.VarGen.fresh_type_var()
          {[param_type | types], ctx}
      end
    end)

    {Enum.reverse(param_types), new_context}
  end

  # Build function type from components
  defp build_function_type([], return_type, effect) do
    Core.function_type({:tuple, []}, effect, return_type)
  end

  defp build_function_type([param], return_type, effect) do
    Core.function_type(param, effect, return_type)
  end

  defp build_function_type(params, return_type, effect) do
    Core.function_type({:tuple, params}, effect, return_type)
  end

  # Extract module name from AST
  defp extract_module_name({:__aliases__, _, parts}) do
    Module.concat(parts)
  end

  defp extract_module_name(atom) when is_atom(atom) do
    atom
  end

  # Fetch AST from compiled module
  defp fetch_module_ast(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, _} ->
        # Try to get source and reparse
        case module.__info__(:compile)[:source] do
          nil ->
            {:error, :no_source}

          source_path ->
            source_path = List.to_string(source_path)

            case File.read(source_path) do
              {:ok, content} ->
                Code.string_to_quoted(content)

              error ->
                error
            end
        end

      _ ->
        {:error, :no_docs}
    end
  end

  # Ensure variable generator is started
  defp ensure_var_gen_started do
    # Using Process dictionary, no need to start anything
    :ok
  end

  # Format error for display
  defp format_error({:cannot_unify, t1, t2}) do
    "Cannot unify types: #{Core.format_type(t1)} with #{Core.format_type(t2)}"
  end

  defp format_error({:cannot_unify_effects, e1, e2}) do
    "Cannot unify effects: #{Core.format_effect(e1)} with #{Core.format_effect(e2)}"
  end

  defp format_error({:undefined_variable, var}) do
    "Undefined variable: #{var}"
  end

  defp format_error({:occurs_check_failed, var, type}) do
    "Infinite type: #{format_var(var)} occurs in #{Core.format_type(type)}"
  end

  defp format_error(error) do
    "Type inference error: #{inspect(error)}"
  end

  defp format_var({:type_var, name}), do: to_string(name)
  defp format_var({:effect_var, name}), do: to_string(name)

  @doc """
  Analyzes multiple files in parallel.
  """
  def analyze_files(paths) when is_list(paths) do
    tasks = Enum.map(paths, fn path ->
      Task.async(fn -> analyze_file(path) end)
    end)

    results = Task.await_many(tasks, :infinity)

    # Combine results
    combined = Enum.reduce(results, {:ok, []}, fn
      {:ok, analysis}, {:ok, acc} ->
        {:ok, [analysis | acc]}

      {:error, _} = error, _ ->
        error

      _, error ->
        error
    end)

    case combined do
      {:ok, analyses} ->
        {:ok, Enum.reverse(analyses)}

      error ->
        error
    end
  end

  @doc """
  Pretty prints analysis results.
  """
  def format_results(%{module: module, functions: functions, errors: errors}) do
    header = "=== Analysis Results for #{module} ===\n"

    functions_str = functions
                    |> Enum.map(fn {{_m, f, a}, analysis} ->
                      type_str = Core.format_type(analysis.type)
                      effect_str = Core.format_effect(analysis.effect)
                      visibility = if analysis[:visibility] == :defp, do: " (private)", else: ""
                      "  #{f}/#{a}#{visibility}:\n    Type: #{type_str}\n    Effect: #{effect_str}"
                    end)
                    |> Enum.join("\n\n")

    errors_str = if Enum.empty?(errors) do
      "  None"
    else
      errors
      |> Enum.map(fn error ->
        {mod, fun, line} = error.location
        "  #{error.type} at #{mod}.#{fun}:#{line}\n    #{error.message}"
      end)
      |> Enum.join("\n\n")
    end

    """
    #{header}

    Functions:
    #{functions_str}

    Errors:
    #{errors_str}
    """
  end

  # Expand only pipe operators in the AST
  # We use Macro.prewalk to recursively expand pipes without expanding other macros
  defp expand_pipes(ast) do
    Macro.prewalk(ast, fn
      {:|>, _, [left, right]} ->
        # Macro.prewalk already handles recursion, so left and right are already processed
        # Just expand this pipe
        case right do
          # Remote call: Module.func(args) becomes Module.func(left, args)
          {{:., meta1, [module, function]}, meta2, args} ->
            {{:., meta1, [module, function]}, meta2, [left | args]}

          # Local call: func(args) becomes func(left, args)
          {function, meta, args} when is_atom(function) and is_list(args) ->
            {function, meta, [left | args]}

          # Function capture: &Module.func/arity becomes Module.func(left)
          {:&, _, [{:/, _, [{{:., meta1, [module, function]}, meta2, []}, _arity]}]} ->
            {{:., meta1, [module, function]}, meta2, [left]}

          # Operator capture: &+/2 becomes +(left)
          {:&, _, [{:/, _, [{operator, meta, _}, _arity]}]} when is_atom(operator) ->
            {operator, meta, [left]}

          # Anything else - call it with left as argument
          _ ->
            {right, [], [left]}
        end

      node ->
        node
    end)
  end
end