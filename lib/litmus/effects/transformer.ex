defmodule Litmus.Effects.Transformer do
  @moduledoc """
  CPS (Continuation-Passing Style) transformer for effect blocks.

  This module walks the AST and transforms effect calls into continuation-passing style,
  while preserving pure code between effects unchanged.

  ## Transformation Strategy

  1. Identify effect call sites using Registry
  2. Transform each effect into a handler call with continuation
  3. Preserve pure code blocks between effects
  4. Handle control flow structures (if/case/cond)
  5. Optimize tail calls

  ## Example Transformation

      # Input AST
      x = File.read!("a.txt")
      y = String.upcase(x)
      File.write!("b.txt", y)

      # Output AST (conceptual)
      __handler__.(
        {File, :read!, ["a.txt"]},
        fn x ->
          y = String.upcase(x)
          __handler__.(
            {File, :write!, ["b.txt", y]},
            fn result -> result end
          )
        end
      )
  """

  alias Litmus.Effects.Registry

  @doc """
  Transforms an AST block into CPS form.

  Returns a transformed AST where effect calls are replaced with handler invocations.
  """
  def transform(ast, opts \\ []) do
    opts = Keyword.validate!(opts, track: :all, passthrough: false)

    # Transform to CPS (macro expansion happens at the call site)
    transform_block(ast, opts)
  end

  @doc """
  Transforms a block (sequence of expressions) into CPS form.
  """
  def transform_block({:__block__, meta, expressions}, opts) do
    # Transform a sequence of expressions
    transform_sequence(expressions, opts, meta)
  end

  def transform_block(single_expression, opts) do
    # Single expression, not a block
    transform_expression(single_expression, opts)
  end

  # Transform a sequence of expressions into nested continuations
  defp transform_sequence([], _opts, _meta) do
    quote do: :ok
  end

  defp transform_sequence([first | rest], opts, meta) do
    # Special case: if rest is empty, this is the last element
    case rest do
      [] ->
        transform_expression(first, opts)

      _non_empty ->
        handler_var = Macro.var(:__handler__, nil)
        handle_multi_element_sequence(first, rest, opts, meta, handler_var)
    end
  end

  # Handle a sequence with at least 2 elements
  defp handle_multi_element_sequence(first, rest, opts, meta, handler_var) do
    case extract_effect(first, opts) do
      {:effect, effect_sig, var_ast} ->
        # This is an effect - create a continuation for the rest
        rest_ast = transform_sequence(rest, opts, meta)

        quote do
          unquote(handler_var).(
            unquote(effect_sig),
            fn unquote(var_ast) ->
              unquote(rest_ast)
            end
          )
        end

      {:control_flow, {:if_assignment, _meta, var_ast, condition, do_branch, else_branch}} ->
        # Transform if with assignment: x = if ... do ... else ... end
        # Both branches need to bind the variable and continue with the rest
        rest_ast = transform_sequence(rest, opts, meta)

        # Transform each branch with the variable binding and continuation
        transformed_do = transform_branch_with_binding(do_branch, var_ast, rest_ast, opts)
        transformed_else = transform_branch_with_binding(else_branch, var_ast, rest_ast, opts)

        quote do
          if unquote(condition) do
            unquote(transformed_do)
          else
            unquote(transformed_else)
          end
        end

      {:control_flow, {:if_bare, _meta, condition, do_branch, else_branch}} ->
        # Transform bare if without assignment
        # Each branch is transformed and then the rest follows
        rest_ast = transform_sequence(rest, opts, meta)

        transformed_do = transform_branch_with_continuation(do_branch, rest_ast, opts)
        transformed_else = transform_branch_with_continuation(else_branch, rest_ast, opts)

        quote do
          if unquote(condition) do
            unquote(transformed_do)
          else
            unquote(transformed_else)
          end
        end

      {:control_flow, {:case_assignment, _meta, var_ast, scrutinee, clauses}} ->
        # Transform case with assignment: x = case expr do ... end
        # All clauses need to bind the variable and continue with the rest
        rest_ast = transform_sequence(rest, opts, meta)

        # Transform each clause body with the variable binding and continuation
        transformed_clauses =
          Enum.map(clauses, fn {:->, clause_meta, [patterns, body]} ->
            transformed_body = transform_branch_with_binding(body, var_ast, rest_ast, opts)
            {:->, clause_meta, [patterns, transformed_body]}
          end)

        quote do
          case unquote(scrutinee) do
            unquote(transformed_clauses)
          end
        end

      {:control_flow, {:case_bare, _meta, scrutinee, clauses}} ->
        # Transform bare case without assignment
        # Each clause is transformed and then the rest follows
        rest_ast = transform_sequence(rest, opts, meta)

        transformed_clauses =
          Enum.map(clauses, fn {:->, clause_meta, [patterns, body]} ->
            transformed_body = transform_branch_with_continuation(body, rest_ast, opts)
            {:->, clause_meta, [patterns, transformed_body]}
          end)

        quote do
          case unquote(scrutinee) do
            unquote(transformed_clauses)
          end
        end

      {:pure, transformed_ast} ->
        # Not an effect - but might be transformed (e.g., function with effects in body)
        case rest do
          [] ->
            # This is the last expression and it's pure - return the transformed version
            transformed_ast

          _ ->
            # More expressions follow
            rest_ast = transform_sequence(rest, opts, meta)

            quote do
              unquote(transformed_ast)
              unquote(rest_ast)
            end
        end
    end
  end

  # Transform a branch and bind the result to a variable, then execute continuation
  defp transform_branch_with_binding(nil, var_ast, continuation, _opts) do
    # nil branch (missing else) - bind nil and continue
    quote do
      unquote(var_ast) = nil
      unquote(continuation)
    end
  end

  defp transform_branch_with_binding(branch, var_ast, continuation, opts) do
    # Transform the branch body
    transformed_branch = transform_block(branch, opts)

    # Wrap in assignment and continuation
    quote do
      unquote(var_ast) = unquote(transformed_branch)
      unquote(continuation)
    end
  end

  # Transform a branch and execute continuation after it
  defp transform_branch_with_continuation(nil, continuation, _opts) do
    # nil branch (missing else) - just execute continuation
    continuation
  end

  defp transform_branch_with_continuation(branch, continuation, opts) do
    # Transform the branch body
    transformed_branch = transform_block(branch, opts)

    # Execute branch then continuation
    quote do
      unquote(transformed_branch)
      unquote(continuation)
    end
  end

  # Transform a single expression
  defp transform_expression(ast, opts) do
    handler_var = Macro.var(:__handler__, nil)

    case extract_effect(ast, opts) do
      {:effect, effect_sig, _var_ast} ->
        # Final effect in the block - tail call optimization
        quote do
          unquote(handler_var).(unquote(effect_sig), fn result -> result end)
        end

      {:control_flow, {:if_assignment, _meta, var_ast, condition, do_branch, else_branch}} ->
        # Final if with assignment - transform branches and return the variable
        transformed_do =
          quote do
            unquote(var_ast) = unquote(transform_block(do_branch, opts))
            unquote(var_ast)
          end

        transformed_else =
          quote do
            unquote(var_ast) = unquote(transform_block(else_branch || quote(do: nil), opts))
            unquote(var_ast)
          end

        quote do
          if unquote(condition) do
            unquote(transformed_do)
          else
            unquote(transformed_else)
          end
        end

      {:control_flow, {:if_bare, _meta, condition, do_branch, else_branch}} ->
        # Final bare if - transform branches and return result
        transformed_do = transform_block(do_branch, opts)
        transformed_else = transform_block(else_branch || quote(do: nil), opts)

        quote do
          if unquote(condition) do
            unquote(transformed_do)
          else
            unquote(transformed_else)
          end
        end

      {:control_flow, {:case_assignment, _meta, var_ast, scrutinee, clauses}} ->
        # Final case with assignment - transform clauses and return the variable
        transformed_clauses =
          Enum.map(clauses, fn {:->, clause_meta, [patterns, body]} ->
            transformed_body =
              quote do
                unquote(var_ast) = unquote(transform_block(body, opts))
                unquote(var_ast)
              end

            {:->, clause_meta, [patterns, transformed_body]}
          end)

        quote do
          case unquote(scrutinee) do
            unquote(transformed_clauses)
          end
        end

      {:control_flow, {:case_bare, _meta, scrutinee, clauses}} ->
        # Final bare case - transform clauses and return result
        transformed_clauses =
          Enum.map(clauses, fn {:->, clause_meta, [patterns, body]} ->
            transformed_body = transform_block(body, opts)
            {:->, clause_meta, [patterns, transformed_body]}
          end)

        quote do
          case unquote(scrutinee) do
            unquote(transformed_clauses)
          end
        end

      {:pure, pure_ast} ->
        # Pure expression - return as is
        pure_ast
    end
  end

  @doc """
  Extracts effect information from an AST node.

  Returns:
  - `{:effect, effect_signature, variable_binding}` if it's an effect
  - `{:pure, ast}` if it's pure code
  - `{:control_flow, transformed_ast}` if it's control flow with effects
  """
  def extract_effect(ast, opts)

  # Match assignment with anonymous function: x = fn ... end
  def extract_effect({:=, meta, [var_ast, {:fn, fn_meta, clauses}]}, opts) do
    # Check if any clause contains effects
    has_effects =
      Enum.any?(clauses, fn {:->, _, [_patterns, body]} -> contains_effect?(body, opts) end)

    if has_effects do
      # Transform each clause body
      transformed_clauses =
        Enum.map(clauses, fn {:->, clause_meta, [patterns, body]} ->
          transformed_body = transform_block(body, opts)
          {:->, clause_meta, [patterns, transformed_body]}
        end)

      # Return transformed function assignment as pure (it's the call that's effectful)
      {:pure, {:=, meta, [var_ast, {:fn, fn_meta, transformed_clauses}]}}
    else
      # No effects in any clause, treat as pure
      {:pure, {:=, meta, [var_ast, {:fn, fn_meta, clauses}]}}
    end
  end

  # Match assignment with if: x = if condition do ... end
  def extract_effect({:=, meta, [var_ast, {:if, if_meta, [condition, branches]}]}, opts) do
    do_branch = Keyword.get(branches, :do)
    else_branch = Keyword.get(branches, :else)

    # Check if either branch contains effects
    if contains_effect?(do_branch, opts) or contains_effect?(else_branch, opts) do
      # This needs special handling - return a marker
      {:control_flow, {:if_assignment, meta, var_ast, condition, do_branch, else_branch}}
    else
      # No effects in either branch, treat as pure
      {:pure, {:=, meta, [var_ast, {:if, if_meta, [condition, branches]}]}}
    end
  end

  # Match bare if: if condition do ... end
  def extract_effect({:if, if_meta, [condition, branches]}, opts) do
    do_branch = Keyword.get(branches, :do)
    else_branch = Keyword.get(branches, :else)

    # Check if either branch contains effects
    if contains_effect?(do_branch, opts) or contains_effect?(else_branch, opts) do
      {:control_flow, {:if_bare, if_meta, condition, do_branch, else_branch}}
    else
      # No effects, treat as pure
      {:pure, {:if, if_meta, [condition, branches]}}
    end
  end

  # Match assignment with case: x = case expr do ... end
  def extract_effect({:=, meta, [var_ast, {:case, case_meta, [scrutinee, [do: clauses]]}]}, opts) do
    # Check if any clause body contains effects
    if Enum.any?(clauses, fn {:->, _, [_pattern, body]} -> contains_effect?(body, opts) end) do
      {:control_flow, {:case_assignment, meta, var_ast, scrutinee, clauses}}
    else
      # No effects in any clause, treat as pure
      {:pure, {:=, meta, [var_ast, {:case, case_meta, [scrutinee, [do: clauses]]}]}}
    end
  end

  # Match bare case: case expr do ... end
  def extract_effect({:case, case_meta, [scrutinee, [do: clauses]]}, opts) do
    # Check if any clause body contains effects
    if Enum.any?(clauses, fn {:->, _, [_pattern, body]} -> contains_effect?(body, opts) end) do
      {:control_flow, {:case_bare, case_meta, scrutinee, clauses}}
    else
      # No effects in any clause, treat as pure
      {:pure, {:case, case_meta, [scrutinee, [do: clauses]]}}
    end
  end

  # Match assignment: x = SomeModule.function(args)
  def extract_effect({:=, _meta, [var_ast, call_ast]}, opts) do
    case extract_call(call_ast, opts) do
      {:effect, effect_sig} ->
        {:effect, effect_sig, var_ast}

      :pure ->
        {:pure, {:=, [], [var_ast, call_ast]}}
    end
  end

  # Match bare function call: SomeModule.function(args)
  def extract_effect(call_ast, opts) do
    case extract_call(call_ast, opts) do
      {:effect, effect_sig} ->
        {:effect, effect_sig, {:_, [], nil}}

      :pure ->
        {:pure, call_ast}
    end
  end

  # Check if an AST node contains any effects
  defp contains_effect?(nil, _opts), do: false

  defp contains_effect?(ast, opts) do
    # Walk the AST and check if there are any effect calls
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        node, false ->
          case extract_call(node, opts) do
            {:effect, _} -> {node, true}
            :pure -> {node, false}
          end

        node, true ->
          {node, true}
      end)

    found
  end

  # Extract module, function, args from a call
  defp extract_call({{:., _dot_meta, [module_ast, function]}, _call_meta, args}, opts) do
    # Handle qualified calls like File.read!(path)
    module = resolve_module(module_ast)
    arity = length(args)

    if should_track_effect?({module, function, arity}, opts) do
      effect_sig =
        quote do
          {unquote(module), unquote(function), [unquote_splicing(args)]}
        end

      {:effect, effect_sig}
    else
      :pure
    end
  end

  # Handle unqualified calls like hd([]) which are implicitly Kernel functions
  defp extract_call({function, _call_meta, args}, opts)
       when is_atom(function) and is_list(args) do
    # Special case: literal constructors and AST structures are not function calls
    # :{} - tuple constructor: {a, b, c}
    # :%{} - map constructor: %{a: 1}
    # :% - struct constructor: %Foo{}
    # :__block__ - block of expressions
    if function in [:{}, :%{}, :%, :__block__] do
      :pure
    else
      arity = length(args)

      # Check if this is a Kernel function effect
      if should_track_effect?({Kernel, function, arity}, opts) do
        effect_sig =
          quote do
            {Kernel, unquote(function), [unquote_splicing(args)]}
          end

        {:effect, effect_sig}
      else
        :pure
      end
    end
  end

  # Handle local calls or other expressions
  defp extract_call(_ast, _opts) do
    :pure
  end

  # Resolve module from AST
  defp resolve_module({:__aliases__, _, parts}) do
    Module.concat(parts)
  end

  defp resolve_module(atom) when is_atom(atom) do
    atom
  end

  defp resolve_module(_) do
    nil
  end

  # Check if we should track this effect
  defp should_track_effect?({module, function, arity}, opts) do
    mfa = {module, function, arity}
    track_option = Keyword.get(opts, :track, :all)

    cond do
      track_option == :all ->
        # Track all effects, but NOT pure functions
        # A function should be tracked if it's in the registry AND not pure
        has_effect = Registry.effect?(mfa) or Registry.effect_module?(module)
        is_pure = Registry.effect_type(mfa) == :p

        has_effect and not is_pure

      is_list(track_option) ->
        # Track only specified categories
        category = Registry.effect_category(mfa)
        category in track_option

      true ->
        false
    end
  end

  @doc """
  Checks if an AST node represents an effect.
  """
  def effect?(ast, opts \\ []) do
    case extract_effect(ast, opts) do
      {:effect, _, _} -> true
      {:pure, _} -> false
    end
  end
end
