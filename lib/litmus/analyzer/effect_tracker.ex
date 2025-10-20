defmodule Litmus.Analyzer.EffectTracker do
  @moduledoc """
  Tracks and analyzes effects through Elixir AST.

  This module identifies effectful operations in code and tracks their
  propagation through the program. It works with the Effects.Registry
  to identify known side-effectful functions.
  """

  alias Litmus.Effects.Registry
  alias Litmus.Types.{Core, Effects}

  @doc """
  Extracts all function calls from an AST.

  Returns a list of MFAs that are called within the expression.

  ## Examples

      iex> ast = quote do: File.read!("test.txt")
      iex> extract_calls(ast)
      [{File, :read!, 1}]
  """
  def extract_calls(ast) do
    # First expand pipes so we get the actual calls
    expanded_ast = expand_pipes(ast)

    {_ast, calls} =
      Macro.prewalk(expanded_ast, [], fn node, acc ->
        case extract_call(node) do
          nil -> {node, acc}
          call -> {node, [call | acc]}
        end
      end)

    calls
    |> Enum.reverse()
    |> Enum.uniq()
  end

  # Expand pipe operators in the AST
  defp expand_pipes(ast) do
    Macro.prewalk(ast, fn
      {:|>, _, [left, right]} ->
        # Expand pipe: left |> right becomes right(left)
        case right do
          {{:., meta1, [module, function]}, meta2, args} ->
            {{:., meta1, [module, function]}, meta2, [left | args]}

          {function, meta, args} when is_atom(function) and is_list(args) ->
            {function, meta, [left | args]}

          {:&, _, [{:/, _, [{{:., meta1, [module, function]}, meta2, []}, _arity]}]} ->
            {{:., meta1, [module, function]}, meta2, [left]}

          {:&, _, [{:/, _, [{operator, meta, _}, _arity]}]} when is_atom(operator) ->
            {operator, meta, [left]}

          _ ->
            {right, [], [left]}
        end

      node ->
        node
    end)
  end

  # Extract MFA from different call forms

  # Function capture: &Module.function/arity
  defp extract_call({:&, _, [{:/, _, [{{:., _, [module, function]}, _, []}, arity]}]})
       when is_atom(function) and is_integer(arity) do
    module = resolve_module(module)
    {module, function, arity}
  end

  # Operator capture: &+/2, &*/2, etc.
  defp extract_call({:&, _, [{:/, _, [{operator, _, _}, arity]}]})
       when is_atom(operator) and is_integer(arity) do
    {Kernel, operator, arity}
  end

  # Regular remote call
  defp extract_call({{:., _, [module, function]}, _, args})
       when is_atom(function) and is_list(args) do
    module = resolve_module(module)
    {module, function, length(args)}
  end

  # Local call
  defp extract_call({function, _, args})
       when is_atom(function) and is_list(args) and function != :fn do
    # Local call - assume Kernel
    {Kernel, function, length(args)}
  end

  defp extract_call(_), do: nil

  @doc """
  Analyzes an AST and returns all effects it may perform.

  Returns a combined effect type representing all possible effects.

  ## Examples

      iex> ast = quote do
      ...>   x = File.read!("test.txt")
      ...>   IO.puts(x)
      ...> end
      iex> analyze_effects(ast)
      {:effect_row, :file, {:effect_label, :io}}
  """
  def analyze_effects(ast) do
    calls = extract_calls(ast)

    calls
    |> Enum.map(&effect_for_call/1)
    |> Enum.reduce(Core.empty_effect(), &Effects.combine_effects/2)
  end

  defp effect_for_call(mfa) do
    Effects.from_mfa(mfa)
  end

  @doc """
  Tracks effect flow through an AST, annotating each node with its effect.

  Returns an annotated AST where each node has effect information attached.
  """
  def annotate_effects(ast) do
    {annotated, _} =
      Macro.prewalk(ast, %{}, fn node, context ->
        effect = node_effect(node, context)
        annotated_node = add_effect_metadata(node, effect)
        new_context = update_context(context, node, effect)
        {annotated_node, new_context}
      end)

    annotated
  end

  # Calculate effect for a single node
  defp node_effect(node, context) do
    case node do
      # Function calls
      {{:., _, [module, function]}, _, args} when is_atom(function) and is_list(args) ->
        module = resolve_module(module)
        mfa = {module, function, length(args)}
        Effects.from_mfa(mfa)

      # Local calls
      {function, _, args} when is_atom(function) and is_list(args) and function != :fn ->
        mfa = {Kernel, function, length(args)}
        Effects.from_mfa(mfa)

      # If expressions - combine branch effects
      {:if, _, [_condition, [do: then_branch, else: else_branch]]} ->
        then_effect = get_cached_effect(context, then_branch, Core.empty_effect())
        else_effect = get_cached_effect(context, else_branch, Core.empty_effect())
        Effects.combine_effects(then_effect, else_effect)

      # Case expressions - combine all clause effects
      {:case, _, [_scrutinee, [do: clauses]]} ->
        clauses
        |> Enum.map(fn {:->, _, [_pattern, body]} ->
          get_cached_effect(context, body, Core.empty_effect())
        end)
        |> Enum.reduce(Core.empty_effect(), &Effects.combine_effects/2)

      # Try-catch blocks
      {:try, _, [[do: try_body, catch: _catch_clauses]]} ->
        try_effect = get_cached_effect(context, try_body, Core.empty_effect())
        # Catch removes exception effect
        Effects.remove_effect(:exn, try_effect) |> elem(0)

      # Blocks - combine all expression effects
      {:__block__, _, expressions} ->
        expressions
        |> Enum.map(&get_cached_effect(context, &1, Core.empty_effect()))
        |> Enum.reduce(Core.empty_effect(), &Effects.combine_effects/2)

      # Default - no effect
      _ ->
        Core.empty_effect()
    end
  end

  # Add effect metadata to a node
  defp add_effect_metadata(node, _effect) do
    # In practice, we'd need a way to attach metadata to AST nodes
    # For now, we'll just return the node unchanged
    # A real implementation might use a wrapper structure or ETS table
    node
  end

  # Update context with node effect information
  defp update_context(context, node, effect) do
    # Store effect for this node
    Map.put(context, node_id(node), effect)
  end

  # Get cached effect from context
  defp get_cached_effect(context, node, default) do
    Map.get(context, node_id(node), default)
  end

  # Generate a unique ID for an AST node
  defp node_id(node) do
    :erlang.phash2(node)
  end

  @doc """
  Checks if an expression is pure (has no side effects).

  ## Examples

      iex> ast = quote do: 1 + 2
      iex> is_pure?(ast)
      true

      iex> ast = quote do: File.read!("test.txt")
      iex> is_pure?(ast)
      false
  """
  def is_pure?(ast) do
    effect = analyze_effects(ast)
    Effects.is_pure?(effect)
  end

  @doc """
  Finds all effectful subexpressions in an AST.

  Returns a list of AST nodes that have side effects.
  """
  def find_effectful_nodes(ast) do
    {_ast, nodes} =
      Macro.prewalk(ast, [], fn node, acc ->
        if is_effectful_node?(node) do
          {node, [node | acc]}
        else
          {node, acc}
        end
      end)

    Enum.reverse(nodes)
  end

  defp is_effectful_node?(node) do
    case node do
      {{:., _, [module, function]}, _, args} when is_atom(function) and is_list(args) ->
        module = resolve_module(module)
        mfa = {module, function, length(args)}
        Registry.effect?(mfa) and Registry.effect_type(mfa) != :p

      {function, _, args} when is_atom(function) and is_list(args) and function != :fn ->
        mfa = {Kernel, function, length(args)}
        Registry.effect?(mfa) and Registry.effect_type(mfa) != :p

      _ ->
        false
    end
  end

  @doc """
  Analyzes effect dependencies between functions.

  Given a map of function definitions, returns a dependency graph
  showing which functions depend on which effects.
  """
  def analyze_dependencies(function_map) when is_map(function_map) do
    function_map
    |> Enum.map(fn {name, ast} ->
      calls = extract_calls(ast)
      effects = analyze_effects(ast)
      {name, %{calls: calls, effects: effects}}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Suggests effect handlers for unhandled effects.

  Given an AST with effects, suggests appropriate handlers.
  """
  def suggest_handlers(ast) do
    effects = analyze_effects(ast)
    effect_list = Effects.to_list(effects)

    case effect_list do
      :unknown ->
        [{:unknown, "Cannot determine specific handlers for unknown effects"}]

      [] ->
        []

      labels ->
        Enum.map(labels, fn label ->
          {label, suggest_handler_for_label(label)}
        end)
    end
  end

  defp suggest_handler_for_label(label) do
    case label do
      :io ->
        "Consider mocking IO operations or using a test-specific IO handler"

      :file ->
        "Consider using in-memory file system or mocking file operations"

      :process ->
        "Consider using supervised test processes or mocking process operations"

      :state ->
        "Consider using controlled state containers or pure state transformations"

      :network ->
        "Consider using mock servers or network stubs"

      :exn ->
        "Consider adding try-catch blocks or using error monads"

      _ ->
        "Consider creating a custom handler for this effect"
    end
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

  @doc """
  Compares effects between two AST nodes.

  Returns :equal, :subset, :superset, or :incompatible.
  """
  def compare_effects(ast1, ast2) do
    effect1 = analyze_effects(ast1)
    effect2 = analyze_effects(ast2)

    cond do
      effect1 == effect2 ->
        :equal

      Effects.subeffect?(effect1, effect2) ->
        :subset

      Effects.subeffect?(effect2, effect1) ->
        :superset

      true ->
        :incompatible
    end
  end
end
