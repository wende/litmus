# Objective 010: Unified Pure Macro Rewrite

## Objective
Complete rewrite of the pure macro to integrate all system improvements: pre-analyze all dependencies, apply CPS transformation before verification, verify effects at AST level rather than runtime, and provide comprehensive runtime enforcement with clear error messages.

## Description
The current pure macro has grown organically with various patches and workarounds. This rewrite consolidates all improvements into a clean, unified implementation that leverages the dependency graph, complete AST analyzer, CPS transformer, and runtime modifier to provide bulletproof purity enforcement with excellent developer experience.

### Key Problems Solved
- Macro expanded before purity checking (effects slip through)
- Verification happens at runtime not compile-time
- No pre-analysis of dependencies
- Poor error messages
- Incomplete integration with new features

## Testing Criteria
1. **Compile-Time Enforcement**
   - All effects detected at compile-time
   - No runtime surprises
   - Clear compilation errors
   - Suggested fixes in error messages

2. **Complete Coverage**
   - All effect leakage paths blocked
   - Works with all language constructs
   - Handles macro-generated code
   - Integrates with CPS transformer

3. **Developer Experience**
   - Fast compilation (< 1s overhead)
   - Excellent error messages
   - Integration with IDEs
   - Debugging support

## Detailed Implementation Guidance

### File: `lib/litmus/pure.ex` (Complete Rewrite)

```elixir
defmodule Litmus.Pure do
  @moduledoc """
  Unified pure macro with complete purity enforcement.
  """

  defmacro pure(opts \\ [], do: block) do
    # Parse options
    opts = parse_options(opts)

    # Phase 1: Pre-analysis at compile time
    pre_analyze_phase(block, opts)

    # Phase 2: AST transformation
    transformed = transform_phase(block, opts)

    # Phase 3: Verification
    verify_phase(transformed, opts)

    # Phase 4: Code generation
    generate_phase(transformed, opts)
  end

  # PHASE 1: Pre-Analysis
  defp pre_analyze_phase(block, opts) do
    quote bind_quoted: [block: block, opts: opts] do
      # Ensure dependency graph is built
      Litmus.Dependency.Graph.ensure_built()

      # Analyze all reachable functions
      Litmus.Analyzer.Complete.ensure_all_analyzed()

      # Warm up effect registry
      Litmus.Effects.Registry.ensure_loaded()
    end
  end

  # PHASE 2: Transformation
  defp transform_phase(block, opts) do
    # Expand macros with tracking
    expanded = expand_with_tracking(block, __CALLER__)

    # Apply CPS transformation if effects are allowed to be caught
    if opts[:catch] do
      Litmus.Effects.Transformer.transform(expanded)
    else
      expanded
    end
  end

  # PHASE 3: Verification
  defp verify_phase(ast, opts) do
    # Extract all function calls
    calls = extract_all_calls(ast)

    # Check each call for purity
    Enum.each(calls, fn call ->
      verify_call_purity(call, opts)
    end)

    # Check for dynamic dispatch
    check_dynamic_dispatch(ast, opts)

    # Check for captured functions
    check_captured_functions(ast, opts)

    # Check for unhandled effects
    if opts[:catch] do
      check_effect_handlers(ast, opts)
    end
  end

  # PHASE 4: Code Generation
  defp generate_phase(transformed, opts) do
    quote do
      # Set up runtime context
      Litmus.Runtime.EffectGuard.enter_pure_context(unquote(opts))

      try do
        # Execute the transformed code
        result = unquote(transformed)

        # Verify no effects leaked
        Litmus.Runtime.EffectGuard.verify_no_effects()

        result
      after
        # Clean up runtime context
        Litmus.Runtime.EffectGuard.exit_pure_context()
      end
    end
  end
end
```

### Key Components

1. **Macro Expansion with Tracking**
   ```elixir
   defp expand_with_tracking(ast, env) do
     # Track macro expansion to detect generated effects
     {expanded, metadata} = Macro.prewalk(ast, %{}, fn node, acc ->
       case node do
         {:__aliases__, _, _} = alias_node ->
           # Expand aliases
           expanded = Macro.expand(alias_node, env)
           {expanded, Map.put(acc, expanded, {:macro, alias_node})}

         {macro, _, _} = macro_call when is_atom(macro) ->
           # Check if this is a macro
           if Macro.macro?(macro, env) do
             expanded = Macro.expand(macro_call, env)
             {expanded, Map.put(acc, expanded, {:macro, macro_call})}
           else
             {node, acc}
           end

         _ ->
           {node, acc}
       end
     end)

     {expanded, metadata}
   end
   ```

2. **Call Extraction and Verification**
   ```elixir
   defp extract_all_calls(ast) do
     {_, calls} = Macro.prewalk(ast, [], fn node, acc ->
       case extract_call(node) do
         {_, _, _} = mfa ->
           {node, [mfa | acc]}
         _ ->
           {node, acc}
       end
     end)

     Enum.uniq(calls)
   end

   defp verify_call_purity({module, function, arity} = mfa, opts) do
     effect = Litmus.Analyzer.Complete.get_effect(mfa)

     case effect do
       :p ->
         :ok  # Pure, allowed

       {:e, exceptions} ->
         verify_exceptions_allowed(exceptions, opts)

       :l ->
         verify_lambda_allowed(mfa, opts)

       effect when effect in [:s, :d, :n, :u] ->
         unless effect_handled?(mfa, opts[:catch]) do
           raise Litmus.ImpurityError,
             mfa: mfa,
             effect_type: effect,
             location: get_location(mfa),
             context: format_context(opts)
         end
     end
   end
   ```

3. **Dynamic Dispatch Detection**
   ```elixir
   defp check_dynamic_dispatch(ast, opts) do
     Macro.prewalk(ast, fn
       {:apply, _, [module, function, args]} = node ->
         unless can_resolve_statically?(module, function) do
           raise Litmus.DynamicDispatchError,
             node: node,
             location: get_location(node),
             suggestion: "Use direct function calls instead of apply/3"
         end
         node

       node ->
         node
     end)
   end
   ```

4. **Effect Handler Verification**
   ```elixir
   defp check_effect_handlers(ast, opts) do
     effects = extract_effects(ast)
     handlers = opts[:catch] || []

     unhandled = Enum.filter(effects, fn effect ->
       not Enum.any?(handlers, &matches_handler?(&1, effect))
     end)

     unless Enum.empty?(unhandled) do
       raise Litmus.UnhandledEffectError,
         effects: unhandled,
         available_handlers: handlers,
         suggestion: format_handler_suggestion(unhandled)
     end
   end
   ```

### Error Messages

```elixir
defmodule Litmus.ImpurityError do
  defexception [:mfa, :effect_type, :location, :context]

  def message(%{mfa: {m, f, a}, effect_type: type, location: loc, context: ctx}) do
    """
    \nImpure function call detected in pure block

    Function: #{inspect(m)}.#{f}/#{a}
    Effect type: #{format_effect(type)}
    Location: #{format_location(loc)}

    #{format_suggestions(type, {m, f, a})}

    Context:
    #{ctx}
    """
  end

  defp format_suggestions(:s, {IO, :puts, 1}) do
    """
    Suggestions:
    • Use the effect macro with a handler:
      effect do
        IO.puts("message")
      catch
        {IO, :puts, [msg]} -> :ok  # Mock the output
      end

    • Move the I/O outside the pure block
    • Use a pure alternative like Logger.debug/1 with a test backend
    """
  end
end
```

### Integration Points

1. **With Dependency Graph**
   ```elixir
   # Pre-analyze in topological order
   graph = Litmus.Dependency.Graph.get_cached()
   Enum.each(graph.analysis_order, &Litmus.Analyzer.Complete.analyze/1)
   ```

2. **With CPS Transformer**
   ```elixir
   # Transform if effects will be caught
   if has_effect_handlers?(opts) do
     Litmus.Effects.Transformer.transform(ast)
   end
   ```

3. **With Runtime Modifier**
   ```elixir
   # Ensure dependencies are modified
   Litmus.Runtime.BeamModifier.ensure_modified(extract_modules(ast))
   ```

## State of Project After Implementation

### Improvements
- **Compile-time detection**: 100% of effects caught at compile-time
- **Error quality**: Clear, actionable error messages
- **Performance**: Minimal overhead with caching
- **Integration**: All features working together

### New Capabilities
- Pre-compilation dependency analysis
- Macro-aware effect tracking
- Dynamic dispatch prevention
- Comprehensive error messages
- IDE integration hooks

### Files Modified
- Rewritten: `lib/litmus/pure.ex`
- Created: `lib/litmus/pure/verifier.ex`
- Created: `lib/litmus/pure/errors.ex`
- Created: `lib/litmus/runtime/effect_guard.ex`
- Updated: All integration points

### Final Test Suite
```elixir
defmodule Litmus.Pure.IntegrationTest do
  use ExUnit.Case

  test "no effect can escape" do
    # All 7 leakage paths blocked
    assert_raise Litmus.ImpurityError, fn ->
      pure do
        IO.puts("test")  # Direct call
      end
    end

    assert_raise Litmus.DynamicDispatchError, fn ->
      pure do
        apply(IO, :puts, ["test"])  # Dynamic dispatch
      end
    end

    assert_raise Litmus.ImpurityError, fn ->
      pure do
        Enum.each([1], &IO.puts/1)  # Captured function
      end
    end

    # ... test all 7 paths ...
  end

  test "complete language support" do
    result = pure do
      with {:ok, x} <- {:ok, 1},
           {:ok, y} <- {:ok, 2} do
        x + y
      end
    end
    assert result == 3
  end
end
```

## Next Recommended Objective

**Continue to Performance Optimization Phase**

With all core features implemented and integrated, the next phase should focus on performance optimization: parallel analysis, incremental compilation, lazy loading, and memory optimization to make Litmus practical for large production codebases. Consider implementing the PLT (Persistent Lookup Table) for cross-project caching and faster startup times.