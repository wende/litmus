defmodule Litmus.Inference.Bidirectional do
  @moduledoc """
  Bidirectional type checking and inference engine.

  Implements the bidirectional typing approach from Dunfield & Krishnaswami (2013),
  extended with effect types. The system has two modes:

  - Synthesis (⇒): Infers types and effects from expressions
  - Checking (⇐): Verifies expressions against expected types and effects

  This approach enables handling of higher-rank polymorphism and effects
  while maintaining decidability.
  """

  alias Litmus.Types.{Core, Effects, Unification, Substitution}
  alias Litmus.Inference.Context

  @type mode :: :synthesis | :checking
  @type result ::
          {:ok, Core.elixir_type(), Core.effect_type(), Substitution.t()}
          | {:error, term()}

  # Counter for generating fresh variables
  defmodule VarGen do
    # Use Process dictionary for simplicity in scripts
    def fresh_type_var do
      n = Process.get(:type_var_counter, 0)
      Process.put(:type_var_counter, n + 1)
      {:type_var, :"t#{n}"}
    end

    def fresh_effect_var do
      n = Process.get(:effect_var_counter, 0)
      Process.put(:effect_var_counter, n + 1)
      {:effect_var, :"e#{n}"}
    end
  end

  @doc """
  Synthesizes a type for an expression.

  Returns the inferred type, effect, and substitution.
  """
  def synthesize(expr, context \\ Context.empty()) do
    infer_type(expr, context, :synthesis, nil)
  end

  @doc """
  Checks an expression against an expected type.

  Returns whether the expression has the expected type and effect.
  """
  def check(expr, expected_type, expected_effect, context \\ Context.empty()) do
    infer_type(expr, context, :checking, {expected_type, expected_effect})
  end

  # Main type inference function
  defp infer_type(expr, context, mode, expected) do
    case expr do
      # Literals - Elixir AST represents them directly
      value when is_integer(value) ->
        handle_literal(:int, context, mode, expected)

      value when is_float(value) ->
        handle_literal(:float, context, mode, expected)

      value when is_binary(value) ->
        handle_literal(:string, context, mode, expected)

      value when is_atom(value) and value in [true, false] ->
        handle_literal(:bool, context, mode, expected)

      value when is_atom(value) and value == nil ->
        handle_literal(:atom, context, mode, expected)

      value when is_atom(value) ->
        # Other atoms (like :ok, :error, etc.)
        handle_literal(:atom, context, mode, expected)

      # Variables (third element can be nil or a module context)
      {name, _, context_atom} when is_atom(name) and is_atom(context_atom) ->
        handle_variable(name, context, mode, expected)

      # Binary/bitstring construction (string interpolation compiles to this)
      # MUST come before local call pattern because {:<<>>, _, args} would match as local call
      {:<<>>, _, segments} ->
        handle_binary(segments, context, mode, expected)

      # Function application (remote call with module.function syntax)
      {{:., _, [module, function]}, _, args} when is_atom(function) ->
        handle_remote_call(module, function, args, context, mode, expected)

      # Function application (calling a function value: func.(args))
      # The dot tuple has [] as second element when it's a function call
      {{:., _, [func_var]}, _, args} ->
        handle_function_application(func_var, args, context, mode, expected)

      # Anonymous function (MUST come before local call pattern!)
      {:fn, _, clauses} ->
        handle_lambda(clauses, context, mode, expected)

      # Function capture operator: &Module.function/arity
      {:&, _, [{:/, _, [{{:., _, [module_ast, function]}, _, []}, arity]}]}
      when is_atom(function) and is_integer(arity) ->
        handle_function_capture(module_ast, function, arity, context, mode, expected)

      # Operator capture: &+/2, &*/2, etc. (Kernel operators)
      {:&, _, [{:/, _, [{operator, _, _}, arity]}]} when is_atom(operator) and is_integer(arity) ->
        # Operators are Kernel functions
        handle_function_capture(
          {:__aliases__, [], [:Kernel]},
          operator,
          arity,
          context,
          mode,
          expected
        )

      # Anonymous capture: &(&1 > 5), &(&1 + &2), etc.
      # These are syntactic sugar for lambdas and should be analyzed as such
      {:&, _, [body]} ->
        handle_anonymous_capture(body, context, mode, expected)

      # Block (MUST come before local call pattern!)
      {:__block__, _, expressions} ->
        handle_block(expressions, context, mode, expected)

      # Module aliases (e.g., ArgumentError, MyModule) - these are compile-time, no effects
      {:__aliases__, _, _parts} ->
        handle_literal(:atom, context, mode, expected)

      # Let binding (Elixir's = is more complex, simplified here)
      {:=, _, [pattern, body]} ->
        handle_let(pattern, body, context, mode, expected)

      # If expression
      {:if, _, [condition, [do: then_branch, else: else_branch]]} ->
        handle_if(condition, then_branch, else_branch, context, mode, expected)

      # Case expression
      {:case, _, [scrutinee, [do: clauses]]} ->
        handle_case(scrutinee, clauses, context, mode, expected)

      {func, meta, args} when is_atom(func) and is_list(args) ->
        handle_local_call(func, meta, args, context, mode, expected)

      # Tuple
      {:{}, _, elements} ->
        handle_tuple(elements, context, mode, expected)

      # Two-element tuple (special syntax)
      {elem1, elem2} ->
        handle_tuple([elem1, elem2], context, mode, expected)

      # List literal
      list when is_list(list) and list != [] ->
        # Check if it's actually a list literal (all elements are not AST nodes)
        # or if it might be something else
        handle_list(list, context, mode, expected)

      # Empty list
      [] ->
        handle_list([], context, mode, expected)

      # Map
      {:%{}, _, pairs} ->
        handle_map(pairs, context, mode, expected)

      # Type operator :: (used in pattern matching and binaries)
      {:"::", _, [value, _type_spec]} ->
        infer_type(value, context, mode, expected)

      # Unknown
      _ ->
        {:error, {:unknown_expression, expr}}
    end
  end

  # Handle literals
  defp handle_literal(type, _context, :synthesis, _expected) do
    {:ok, type, Core.empty_effect(), Substitution.empty()}
  end

  defp handle_literal(type, _context, :checking, {expected_type, expected_effect}) do
    with {:ok, subst} <- Unification.unify(type, expected_type),
         {:ok, subst2} <- Unification.unify_effect(Core.empty_effect(), expected_effect) do
      {:ok, type, Core.empty_effect(), Substitution.compose(subst, subst2)}
    end
  end

  # Handle variables
  defp handle_variable(name, context, :synthesis, _expected) do
    case Context.lookup(context, name) do
      {:ok, type} ->
        # Instantiate polymorphic types
        {instantiated, effect} = instantiate_type(type)
        {:ok, instantiated, effect, Substitution.empty()}

      :error ->
        # Unknown variable - create fresh type variable
        # Variables (like function parameters) are values, not computations
        # They have no effects themselves (empty effect)
        var = VarGen.fresh_type_var()
        {:ok, var, Core.empty_effect(), Substitution.empty()}
    end
  end

  defp handle_variable(name, context, :checking, {expected_type, expected_effect}) do
    case Context.lookup(context, name) do
      {:ok, type} ->
        {instantiated, _effect} = instantiate_type(type)

        with {:ok, subst} <- Unification.unify(instantiated, expected_type),
             {:ok, subst2} <- Unification.unify_effect(Core.empty_effect(), expected_effect) do
          {:ok, expected_type, expected_effect, Substitution.compose(subst, subst2)}
        end

      :error ->
        {:error, {:undefined_variable, name}}
    end
  end

  # Handle remote function calls (Module.function)
  defp handle_remote_call(module_ast, function, args, context, mode, expected) do
    module = resolve_module(module_ast)

    # Get effect from registry
    arity = length(args)
    effect = Effects.from_mfa({module, function, arity})

    # Infer argument types
    arg_results = Enum.map(args, &synthesize(&1, context))

    # Check if all succeeded
    case Enum.find(arg_results, &match?({:error, _}, &1)) do
      {:error, _} = error ->
        error

      nil ->
        arg_types = Enum.map(arg_results, fn {:ok, type, _, _} -> type end)
        arg_effects = Enum.map(arg_results, fn {:ok, _, eff, _} -> eff end)
        arg_substs = Enum.map(arg_results, fn {:ok, _, _, subst} -> subst end)

        # Special handling for higher-order functions
        # Extract lambda effects for:
        # 1. Functions marked as 'u' (unknown) - we need to infer from the lambda
        # 2. Functions marked as 'l' (lambda-dependent) - the effect depends on the lambda

        # Check if there are any lambda arguments
        has_lambda_args = Enum.any?(arg_types, &match?({:function, _, _, _}, &1))

        # Extract lambda effects if:
        # 1. There are lambda arguments, AND
        # 2. The registry effect is unknown OR lambda-dependent
        is_lambda_dependent =
          case effect do
            {:effect_label, :lambda} -> true
            {:effect_row, labels, _} -> :lambda in labels
            _ -> false
          end

        should_extract_lambda_effects =
          has_lambda_args and
            (match?({:effect_unknown}, effect) or is_lambda_dependent)

        combined_effect =
          if should_extract_lambda_effects do
            # Extract effects from lambda arguments
            lambda_effects =
              arg_types
              |> Enum.zip(args)
              |> Enum.flat_map(fn
                {{:function, _param_type, lambda_effect, _return_type}, _arg_ast} ->
                  # This argument is a lambda, include its effect
                  [lambda_effect]

                _ ->
                  []
              end)

            # For lambda-dependent functions, use the lambda's actual effects
            # For unknown functions, infer from lambda + arg effects
            all_effects = arg_effects ++ lambda_effects

            inferred_effect =
              Enum.reduce(all_effects, Core.empty_effect(), &Effects.combine_effects/2)

            # Only wrap with :lambda if the inferred effect has unknown/variable effects
            # If all lambda effects are concrete (pure, side effects, etc.), use those directly
            if Enum.any?(lambda_effects, &match?({:effect_unknown}, &1)) do
              # Has unknown lambda effects, mark as lambda-dependent
              Effects.combine_effects({:effect_label, :lambda}, inferred_effect)
            else
              # All lambda effects are known, use them directly
              inferred_effect
            end
          else
            # Normal function or function with concrete effects in registry:
            # Just combine argument construction effects with function's effect from registry
            Enum.reduce(arg_effects, effect, &Effects.combine_effects/2)
          end

        combined_subst = Enum.reduce(arg_substs, Substitution.empty(), &Substitution.compose/2)

        # For now, assume return type is a fresh variable
        return_type = VarGen.fresh_type_var()

        case mode do
          :synthesis ->
            {:ok, return_type, combined_effect, combined_subst}

          :checking ->
            {expected_type, expected_effect} = expected

            with {:ok, subst} <- Unification.unify(return_type, expected_type),
                 {:ok, subst2} <- Unification.unify_effect(combined_effect, expected_effect) do
              final_subst =
                Substitution.compose(
                  combined_subst,
                  Substitution.compose(subst, subst2)
                )

              {:ok, expected_type, expected_effect, final_subst}
            end
        end
    end
  end

  # Handle function application (calling a function stored in a variable)
  defp handle_function_application(func_var, args, context, mode, expected) do
    # Synthesize the function variable to get its type
    case synthesize(func_var, context) do
      {:ok, {:function, _param_type, func_effect, return_type}, _var_effect, var_subst} ->
        # The function has a known function type with an effect
        # Synthesize arguments
        arg_results = Enum.map(args, &synthesize(&1, context))

        case Enum.find(arg_results, &match?({:error, _}, &1)) do
          {:error, _} = error ->
            error

          nil ->
            arg_effects = Enum.map(arg_results, fn {:ok, _, eff, _} -> eff end)
            arg_substs = Enum.map(arg_results, fn {:ok, _, _, subst} -> subst end)

            # Combine: argument effects + function effect
            combined_effect = Enum.reduce(arg_effects, func_effect, &Effects.combine_effects/2)

            combined_subst =
              Enum.reduce([var_subst | arg_substs], Substitution.empty(), &Substitution.compose/2)

            case mode do
              :synthesis ->
                {:ok, return_type, combined_effect, combined_subst}

              :checking ->
                {expected_type, expected_effect} = expected

                with {:ok, subst} <- Unification.unify(return_type, expected_type),
                     {:ok, subst2} <- Unification.unify_effect(combined_effect, expected_effect) do
                  final_subst =
                    Substitution.compose(combined_subst, Substitution.compose(subst, subst2))

                  {:ok, expected_type, expected_effect, final_subst}
                end
            end
        end

      {:ok, _other_type, _effect, _subst} ->
        # The function variable doesn't have a concrete function type yet
        # This is common for function parameters
        # Return unknown effect and fresh type variable
        arg_results = Enum.map(args, &synthesize(&1, context))

        case Enum.find(arg_results, &match?({:error, _}, &1)) do
          {:error, _} = error ->
            error

          nil ->
            arg_effects = Enum.map(arg_results, fn {:ok, _, eff, _} -> eff end)
            arg_substs = Enum.map(arg_results, fn {:ok, _, _, subst} -> subst end)

            # Unknown function call - combine argument effects with fresh effect var
            combined_effect =
              Enum.reduce(arg_effects, VarGen.fresh_effect_var(), &Effects.combine_effects/2)

            combined_subst =
              Enum.reduce(arg_substs, Substitution.empty(), &Substitution.compose/2)

            return_type = VarGen.fresh_type_var()

            case mode do
              :synthesis ->
                {:ok, return_type, combined_effect, combined_subst}

              :checking ->
                {expected_type, expected_effect} = expected

                with {:ok, subst} <- Unification.unify(return_type, expected_type),
                     {:ok, subst2} <- Unification.unify_effect(combined_effect, expected_effect) do
                  final_subst =
                    Substitution.compose(combined_subst, Substitution.compose(subst, subst2))

                  {:ok, expected_type, expected_effect, final_subst}
                end
            end
        end

      error ->
        error
    end
  end

  # Handle local function calls
  defp handle_local_call(func, _meta, args, context, mode, expected) do
    # When analyzing files statically, the meta doesn't include imports information
    # So we can't rely on meta[:imports] to determine if it's a Kernel function
    # Instead, we check if the function exists in the Kernel module's registry

    arity = length(args)

    # Try to get effect from Kernel registry
    # If it exists, this is a Kernel function
    # Use try/catch to handle MissingStdlibEffectError gracefully
    is_kernel =
      try do
        effect = Litmus.Effects.Registry.effect_type({Kernel, func, arity})
        effect != nil
      rescue
        _ -> false
      end

    if is_kernel do
      # It's a Kernel function, handle it normally
      handle_remote_call(Kernel, func, args, context, mode, expected)
    else
      # Treat as a local module function
      # For now, we'll assume local functions have unknown effects
      arg_results = Enum.map(args, &synthesize(&1, context))

      case Enum.find(arg_results, &match?({:error, _}, &1)) do
        {:error, _} = error ->
          error

        nil ->
          _arg_types = Enum.map(arg_results, fn {:ok, type, _, _} -> type end)
          arg_effects = Enum.map(arg_results, fn {:ok, _, eff, _} -> eff end)
          arg_substs = Enum.map(arg_results, fn {:ok, _, _, subst} -> subst end)

          # Combine argument effects with unknown function effect
          combined_effect =
            Enum.reduce(arg_effects, VarGen.fresh_effect_var(), &Effects.combine_effects/2)

          combined_subst = Enum.reduce(arg_substs, Substitution.empty(), &Substitution.compose/2)

          return_type = VarGen.fresh_type_var()

          case mode do
            :synthesis ->
              {:ok, return_type, combined_effect, combined_subst}

            :checking ->
              {expected_type, expected_effect} = expected

              with {:ok, subst} <- Unification.unify(return_type, expected_type),
                   {:ok, subst2} <- Unification.unify_effect(combined_effect, expected_effect) do
                final_subst =
                  Substitution.compose(
                    combined_subst,
                    Substitution.compose(subst, subst2)
                  )

                {:ok, expected_type, expected_effect, final_subst}
              end
          end
      end
    end
  end

  # Handle function capture: &Module.function/arity
  defp handle_function_capture(module_ast, function, arity, _context, _mode, _expected) do
    # Resolve the module
    module = resolve_module(module_ast)

    # Get the effect of the captured function from the registry
    mfa = {module, function, arity}
    effect = Effects.from_mfa(mfa)

    # Create a function type for the capture
    # We use fresh type variables for parameter and return types
    param_type = VarGen.fresh_type_var()
    return_type = VarGen.fresh_type_var()

    # The captured function has the effect from the registry
    fun_type = Core.function_type(param_type, effect, return_type)

    # Capturing a function reference is pure - the effect happens when it's called
    {:ok, fun_type, Core.empty_effect(), Substitution.empty()}
  end

  # Handle anonymous captures: &(&1 > 5), &(&1 + &2), etc.
  defp handle_anonymous_capture(body, context, mode, expected) do
    # Find the maximum argument number used in the capture
    arity = find_max_capture_arg(body)

    # Create parameter names and variables
    params = for i <- 1..arity, do: {:"arg#{i}", [], Elixir}

    # Transform the body by replacing {:&, [], [n]} with the corresponding parameter
    transformed_body = transform_capture_body(body, params)

    # Create a lambda clause
    lambda_clause = {:->, [], [params, transformed_body]}

    # Analyze as a lambda
    handle_lambda([lambda_clause], context, mode, expected)
  end

  # Find the maximum capture argument number (&1, &2, etc.) in an expression
  defp find_max_capture_arg(ast) do
    {_, max} =
      Macro.prewalk(ast, 0, fn node, max ->
        case node do
          {:&, _, [n]} when is_integer(n) and n > 0 ->
            {{:&, [], [n]}, max(max, n)}

          _ ->
            {node, max}
        end
      end)

    max
  end

  # Transform capture body by replacing {:&, [], [n]} with parameter variables
  defp transform_capture_body(body, params) do
    Macro.prewalk(body, fn node ->
      case node do
        {:&, _, [n]} when is_integer(n) and n > 0 ->
          # Replace &n with the nth parameter (1-indexed)
          Enum.at(params, n - 1)

        _ ->
          node
      end
    end)
  end

  # Handle lambda expressions
  defp handle_lambda(clauses, context, mode, expected) do
    case mode do
      :synthesis ->
        synthesize_lambda(clauses, context)

      :checking ->
        {expected_type, expected_effect} = expected
        check_lambda(clauses, context, expected_type, expected_effect)
    end
  end

  defp synthesize_lambda([{:->, _, [params, body]}], context) when is_list(params) do
    # Single clause lambda with one or more parameters
    # Create fresh type variables for each parameter
    {param_types, new_context} =
      Enum.reduce(params, {[], context}, fn param, {types, ctx} ->
        param_type = VarGen.fresh_type_var()
        param_name = extract_param_name(param)
        {[param_type | types], Context.add(ctx, param_name, param_type)}
      end)

    param_types = Enum.reverse(param_types)

    # Synthesize body type
    case synthesize(body, new_context) do
      {:ok, body_type, body_effect, subst} ->
        # Build function type based on number of parameters
        fun_type =
          case param_types do
            [] ->
              # Zero-arity function
              Core.function_type({:tuple, []}, body_effect, body_type)

            [single] ->
              # Single parameter
              Core.function_type(single, body_effect, body_type)

            multiple ->
              # Multiple parameters - use tuple
              Core.function_type({:tuple, multiple}, body_effect, body_type)
          end

        {:ok, fun_type, Core.empty_effect(), subst}

      error ->
        error
    end
  end

  defp synthesize_lambda(_, _context) do
    # Multi-clause lambdas not yet supported
    {:error, :complex_lambda_not_supported}
  end

  defp check_lambda([{:->, _, [params, body]}], context, expected_type, _expected_effect)
       when is_list(params) do
    case expected_type do
      {:function, param_type, effect, return_type} ->
        # Extract expected parameter types
        expected_param_types =
          case param_type do
            {:tuple, types} -> types
            single -> [single]
          end

        # Check that parameter count matches
        if length(params) != length(expected_param_types) do
          {:error, {:arity_mismatch, length(params), length(expected_param_types)}}
        else
          # Add all parameters to context with their expected types
          new_context =
            Enum.zip(params, expected_param_types)
            |> Enum.reduce(context, fn {param, param_type}, ctx ->
              param_name = extract_param_name(param)
              Context.add(ctx, param_name, param_type)
            end)

          # Check body against expected return type and effect
          check(body, return_type, effect, new_context)
        end

      _ ->
        {:error, {:expected_function_type, expected_type}}
    end
  end

  defp check_lambda(_, _context, _expected_type, _expected_effect) do
    {:error, :complex_lambda_not_supported}
  end

  # Handle let bindings
  defp handle_let(pattern, body, context, _mode, _expected) do
    # Simplified: only handle simple variable patterns
    case pattern do
      # Variable pattern can have any atom context (nil, Elixir, module name, etc.)
      {var_name, _, context_atom} when is_atom(var_name) and is_atom(context_atom) ->
        # Synthesize type of body
        case synthesize(body, context) do
          {:ok, body_type, body_effect, subst} ->
            # Check if pure for generalization
            if Effects.is_pure?(body_effect) do
              # Can generalize
              gen_type = generalize(body_type, context)
              _new_context = Context.add(context, var_name, gen_type)
              {:ok, body_type, body_effect, subst}
            else
              # Cannot generalize effectful expressions
              _new_context = Context.add(context, var_name, body_type)
              {:ok, body_type, body_effect, subst}
            end

          error ->
            error
        end

      _ ->
        {:error, :complex_pattern_not_supported}
    end
  end

  # Handle if expressions
  defp handle_if(condition, then_branch, else_branch, context, mode, expected) do
    # Check condition is boolean
    case synthesize(condition, context) do
      {:ok, cond_type, cond_effect, cond_subst} ->
        with {:ok, bool_subst} <- Unification.unify(cond_type, :bool) do
          # Synthesize or check branches
          case mode do
            :synthesis ->
              synthesize_if_branches(
                then_branch,
                else_branch,
                context,
                cond_effect,
                Substitution.compose(cond_subst, bool_subst)
              )

            :checking ->
              {expected_type, expected_effect} = expected

              check_if_branches(
                then_branch,
                else_branch,
                context,
                expected_type,
                expected_effect,
                cond_effect,
                Substitution.compose(cond_subst, bool_subst)
              )
          end
        end

      error ->
        error
    end
  end

  defp synthesize_if_branches(then_branch, else_branch, context, cond_effect, subst) do
    case {synthesize(then_branch, context), synthesize(else_branch, context)} do
      {{:ok, then_type, then_effect, then_subst}, {:ok, else_type, else_effect, else_subst}} ->
        # Unify branch types
        with {:ok, type_subst} <- Unification.unify(then_type, else_type) do
          # Combine effects
          branch_effects = Effects.combine_effects(then_effect, else_effect)
          total_effect = Effects.combine_effects(cond_effect, branch_effects)

          final_subst =
            [subst, then_subst, else_subst, type_subst]
            |> Enum.reduce(Substitution.empty(), &Substitution.compose/2)

          unified_type = Substitution.apply_subst(final_subst, then_type)
          {:ok, unified_type, total_effect, final_subst}
        end

      _ ->
        {:error, :if_branch_synthesis_failed}
    end
  end

  defp check_if_branches(
         then_branch,
         else_branch,
         context,
         expected_type,
         expected_effect,
         cond_effect,
         subst
       ) do
    # Check both branches against expected type
    remaining_effect = remove_effect_prefix(expected_effect, cond_effect)

    case {check(then_branch, expected_type, remaining_effect, context),
          check(else_branch, expected_type, remaining_effect, context)} do
      {{:ok, _, _, then_subst}, {:ok, _, _, else_subst}} ->
        final_subst =
          [subst, then_subst, else_subst]
          |> Enum.reduce(Substitution.empty(), &Substitution.compose/2)

        {:ok, expected_type, expected_effect, final_subst}

      _ ->
        {:error, :if_branch_check_failed}
    end
  end

  # Handle case expressions
  defp handle_case(scrutinee, clauses, context, mode, expected) do
    # Synthesize the scrutinee type
    case synthesize(scrutinee, context) do
      {:ok, _scrutinee_type, scrutinee_effect, scrutinee_subst} ->
        # Analyze all case clauses
        case mode do
          :synthesis ->
            synthesize_case_clauses(clauses, context, scrutinee_effect, scrutinee_subst)

          :checking ->
            {expected_type, expected_effect} = expected

            check_case_clauses(
              clauses,
              context,
              expected_type,
              expected_effect,
              scrutinee_effect,
              scrutinee_subst
            )
        end

      error ->
        error
    end
  end

  defp synthesize_case_clauses([], _context, _scrutinee_effect, _subst) do
    {:error, :empty_case}
  end

  defp synthesize_case_clauses(clauses, context, scrutinee_effect, subst) do
    # Synthesize each clause body
    clause_results =
      Enum.map(clauses, fn {:->, _, [_pattern, body]} ->
        synthesize(body, context)
      end)

    # Check if any clause failed
    case Enum.find(clause_results, &match?({:error, _}, &1)) do
      {:error, _} = error ->
        error

      nil ->
        # Extract types, effects, and substitutions
        clause_types = Enum.map(clause_results, fn {:ok, type, _, _} -> type end)
        clause_effects = Enum.map(clause_results, fn {:ok, _, eff, _} -> eff end)
        clause_substs = Enum.map(clause_results, fn {:ok, _, _, s} -> s end)

        # Unify all clause types to get a common return type
        case unify_all_types(clause_types) do
          {:ok, unified_type, type_subst} ->
            # Combine all effects
            combined_clause_effects =
              Enum.reduce(clause_effects, Core.empty_effect(), &Effects.combine_effects/2)

            total_effect = Effects.combine_effects(scrutinee_effect, combined_clause_effects)

            # Compose all substitutions
            all_substs = [subst, type_subst | clause_substs]
            final_subst = Enum.reduce(all_substs, Substitution.empty(), &Substitution.compose/2)

            final_type = Substitution.apply_subst(final_subst, unified_type)
            {:ok, final_type, total_effect, final_subst}

          {:error, _} = error ->
            error
        end
    end
  end

  defp check_case_clauses(
         clauses,
         context,
         expected_type,
         expected_effect,
         scrutinee_effect,
         subst
       ) do
    # Remove scrutinee effect from expected effect
    remaining_effect = remove_effect_prefix(expected_effect, scrutinee_effect)

    # Check each clause body against expected type
    clause_results =
      Enum.map(clauses, fn {:->, _, [_pattern, body]} ->
        check(body, context, expected_type, remaining_effect)
      end)

    # Check if any clause failed
    case Enum.find(clause_results, &match?({:error, _}, &1)) do
      {:error, _} = error ->
        error

      nil ->
        # Extract effects and substitutions
        clause_effects = Enum.map(clause_results, fn {:ok, _, eff, _} -> eff end)
        clause_substs = Enum.map(clause_results, fn {:ok, _, _, s} -> s end)

        # Combine all effects
        combined_clause_effects =
          Enum.reduce(clause_effects, Core.empty_effect(), &Effects.combine_effects/2)

        total_effect = Effects.combine_effects(scrutinee_effect, combined_clause_effects)

        # Compose all substitutions
        all_substs = [subst | clause_substs]
        final_subst = Enum.reduce(all_substs, Substitution.empty(), &Substitution.compose/2)

        {:ok, expected_type, total_effect, final_subst}
    end
  end

  # Helper to unify all types in a list
  defp unify_all_types([]), do: {:ok, VarGen.fresh_type_var(), Substitution.empty()}
  defp unify_all_types([single]), do: {:ok, single, Substitution.empty()}

  defp unify_all_types([first | rest]) do
    Enum.reduce_while(rest, {:ok, first, Substitution.empty()}, fn type,
                                                                   {:ok, acc_type, acc_subst} ->
      case Unification.unify(acc_type, type) do
        {:ok, new_subst} ->
          unified = Substitution.apply_subst(new_subst, acc_type)
          final_subst = Substitution.compose(acc_subst, new_subst)
          {:cont, {:ok, unified, final_subst}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  # Handle blocks
  defp handle_block([], _context, _mode, _expected) do
    # Empty block returns nil
    {:ok, :atom, Core.empty_effect(), Substitution.empty()}
  end

  defp handle_block([expr], context, mode, expected) do
    infer_type(expr, context, mode, expected)
  end

  defp handle_block([expr | rest], context, _mode, _expected) do
    # Special handling for let bindings to thread context
    case expr do
      {:=, _, [pattern, body]} when is_tuple(pattern) ->
        # Let binding - extract variable name and synthesize body
        case pattern do
          {var_name, _, context_atom} when is_atom(var_name) and is_atom(context_atom) ->
            # Synthesize the right-hand side
            case synthesize(body, context) do
              {:ok, body_type, body_effect, subst} ->
                # Add variable to context for subsequent expressions
                new_context = Context.add(context, var_name, body_type)

                # Continue with rest of block using updated context
                case handle_block(rest, new_context, :synthesis, nil) do
                  {:ok, rest_type, rest_effect, rest_subst} ->
                    combined_effect = Effects.combine_effects(body_effect, rest_effect)
                    combined_subst = Substitution.compose(subst, rest_subst)
                    {:ok, rest_type, combined_effect, combined_subst}

                  error ->
                    error
                end

              error ->
                error
            end

          _ ->
            # Complex pattern - fall back to default handling
            synthesize_expr_and_continue(expr, rest, context)
        end

      _ ->
        # Not a let binding - normal handling
        synthesize_expr_and_continue(expr, rest, context)
    end
  end

  # Helper for non-let expressions in blocks
  defp synthesize_expr_and_continue(expr, rest, context) do
    case synthesize(expr, context) do
      {:ok, _type, effect, subst} ->
        # Update context with substitution
        new_context = Context.apply_substitution(context, subst)

        # Continue with rest
        case handle_block(rest, new_context, :synthesis, nil) do
          {:ok, rest_type, rest_effect, rest_subst} ->
            combined_effect = Effects.combine_effects(effect, rest_effect)
            combined_subst = Substitution.compose(subst, rest_subst)
            {:ok, rest_type, combined_effect, combined_subst}

          error ->
            error
        end

      error ->
        error
    end
  end

  # Handle tuples
  defp handle_tuple(elements, context, :synthesis, _expected) do
    results = Enum.map(elements, &synthesize(&1, context))

    case Enum.find(results, &match?({:error, _}, &1)) do
      {:error, _} = error ->
        error

      nil ->
        types = Enum.map(results, fn {:ok, type, _, _} -> type end)
        effects = Enum.map(results, fn {:ok, _, eff, _} -> eff end)
        substs = Enum.map(results, fn {:ok, _, _, subst} -> subst end)

        combined_effect = Enum.reduce(effects, Core.empty_effect(), &Effects.combine_effects/2)
        combined_subst = Enum.reduce(substs, Substitution.empty(), &Substitution.compose/2)

        {:ok, {:tuple, types}, combined_effect, combined_subst}
    end
  end

  defp handle_tuple(elements, context, :checking, {expected_type, expected_effect}) do
    case expected_type do
      {:tuple, expected_types} when length(expected_types) == length(elements) ->
        # Check each element
        check_results =
          Enum.zip(elements, expected_types)
          |> Enum.map(fn {elem, exp_type} ->
            check(elem, exp_type, expected_effect, context)
          end)

        case Enum.find(check_results, &match?({:error, _}, &1)) do
          {:error, _} = error ->
            error

          nil ->
            substs = Enum.map(check_results, fn {:ok, _, _, subst} -> subst end)
            combined_subst = Enum.reduce(substs, Substitution.empty(), &Substitution.compose/2)
            {:ok, expected_type, expected_effect, combined_subst}
        end

      _ ->
        {:error, {:expected_tuple_type, expected_type}}
    end
  end

  # Handle lists
  defp handle_list([], _context, :synthesis, _expected) do
    elem_type = VarGen.fresh_type_var()
    {:ok, {:list, elem_type}, Core.empty_effect(), Substitution.empty()}
  end

  defp handle_list([head | tail], context, :synthesis, _expected) do
    case synthesize(head, context) do
      {:ok, head_type, head_effect, head_subst} ->
        case handle_list(tail, context, :synthesis, nil) do
          {:ok, {:list, tail_elem_type}, tail_effect, tail_subst} ->
            # Unify element types
            with {:ok, elem_subst} <- Unification.unify(head_type, tail_elem_type) do
              combined_effect = Effects.combine_effects(head_effect, tail_effect)

              combined_subst =
                [head_subst, tail_subst, elem_subst]
                |> Enum.reduce(Substitution.empty(), &Substitution.compose/2)

              unified_type = Substitution.apply_subst(combined_subst, head_type)
              {:ok, {:list, unified_type}, combined_effect, combined_subst}
            end

          error ->
            error
        end

      error ->
        error
    end
  end

  defp handle_list(elements, context, :checking, {expected_type, expected_effect}) do
    case expected_type do
      {:list, elem_type} ->
        # Check all elements against element type
        check_results = Enum.map(elements, &check(&1, elem_type, expected_effect, context))

        case Enum.find(check_results, &match?({:error, _}, &1)) do
          {:error, _} = error ->
            error

          nil ->
            substs = Enum.map(check_results, fn {:ok, _, _, subst} -> subst end)
            combined_subst = Enum.reduce(substs, Substitution.empty(), &Substitution.compose/2)
            {:ok, expected_type, expected_effect, combined_subst}
        end

      _ ->
        {:error, {:expected_list_type, expected_type}}
    end
  end

  # Handle maps (simplified)
  defp handle_map(_pairs, _context, _mode, _expected) do
    {:error, :maps_not_yet_implemented}
  end

  # Handle binary construction (string interpolation)
  defp handle_binary(segments, context, :synthesis, _expected) do
    # Analyze each segment for effects
    results =
      Enum.map(segments, fn segment ->
        case segment do
          {:"::", _, [value, _type]} ->
            synthesize(value, context)

          value ->
            synthesize(value, context)
        end
      end)

    # Check if any segment failed
    case Enum.find(results, &match?({:error, _}, &1)) do
      {:error, _} = error ->
        error

      nil ->
        # Combine effects from all segments
        effects = Enum.map(results, fn {:ok, _, eff, _} -> eff end)
        substs = Enum.map(results, fn {:ok, _, _, subst} -> subst end)

        combined_effect = Enum.reduce(effects, Core.empty_effect(), &Effects.combine_effects/2)
        combined_subst = Enum.reduce(substs, Substitution.empty(), &Substitution.compose/2)

        # Binary always results in a string
        {:ok, :string, combined_effect, combined_subst}
    end
  end

  defp handle_binary(_segments, _context, :checking, {expected_type, expected_effect}) do
    # In checking mode, just verify it's a string type
    with {:ok, subst} <- Unification.unify(:string, expected_type) do
      {:ok, expected_type, expected_effect, subst}
    end
  end

  # Helper functions

  defp resolve_module({:__aliases__, _, parts}) do
    Module.concat(parts)
  end

  defp resolve_module(atom) when is_atom(atom) do
    atom
  end

  # Handle variable/dynamic module references
  defp resolve_module({var, _, _}) when is_atom(var) do
    # Return a placeholder for dynamic module calls
    :dynamic_module
  end

  defp resolve_module(_) do
    # Unknown module reference
    :unknown_module
  end

  defp extract_param_name({name, _, nil}) when is_atom(name), do: name
  defp extract_param_name(_), do: :_

  defp instantiate_type({:forall, vars, body}) do
    # Replace quantified variables with fresh ones
    fresh_vars =
      Enum.map(vars, fn
        {:type_var, _} -> VarGen.fresh_type_var()
        {:effect_var, _} -> VarGen.fresh_effect_var()
      end)

    subst = Enum.zip(vars, fresh_vars) |> Enum.into(%{})
    instantiated = Substitution.apply_subst(subst, body)

    # Extract effect if it's a function type
    effect =
      case instantiated do
        {:function, _, eff, _} -> eff
        _ -> Core.empty_effect()
      end

    {instantiated, effect}
  end

  defp instantiate_type(type) do
    {type, Core.empty_effect()}
  end

  defp generalize(type, _context) do
    # Collect free variables
    free_vars = Core.free_variables(type) |> MapSet.to_list()

    if Enum.empty?(free_vars) do
      type
    else
      {:forall, free_vars, type}
    end
  end

  defp remove_effect_prefix(effect, prefix) do
    # Try to remove prefix from effect
    case Effects.combine_effects(prefix, Core.empty_effect()) do
      ^effect -> Core.empty_effect()
      # Can't remove, return as is
      _ -> effect
    end
  end
end
