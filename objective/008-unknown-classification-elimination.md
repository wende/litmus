# Objective 008: Unknown Classification Elimination

## Objective
Eliminate the remaining :unknown effect classifications by implementing conservative inference strategies, improving dynamic dispatch analysis, adding metaprogramming support, and developing smarter heuristics to achieve near-zero unknowns.

## Description
Currently ~5-15% of functions are marked :unknown due to dynamic dispatch, missing source code, complex macros, or forward references. This objective implements multiple strategies to infer effects even when perfect static analysis isn't possible, using conservative assumptions, pattern recognition, and contextual clues to provide useful classifications instead of giving up.

### Key Problems Solved
- Dynamic dispatch (`apply/3`) marked as :unknown
- Missing source code leads to :unknown
- Complex macros generate :unknown
- Forward references create cascading unknowns
- No fallback inference strategies

## Testing Criteria
1. **Classification Coverage**
   - <1% of functions marked :unknown in typical projects
   - All stdlib functions have known classifications
   - Dynamic dispatch resolved when possible
   - Conservative inference for missing sources

2. **Inference Accuracy**
   - Conservative assumptions (prefer false positives over false negatives)
   - Pattern-based inference >80% accurate
   - Context-aware inference improves precision
   - Never misclassify impure as pure

3. **Strategies Applied**
   - Naming convention heuristics
   - Module context inference
   - Common pattern recognition
   - Data flow analysis for dynamic dispatch
   - Macro expansion with context

## Detailed Implementation Guidance

### File: `lib/litmus/analyzer/unknown_eliminator.ex`

```elixir
defmodule Litmus.Analyzer.UnknownEliminator do
  @moduledoc """
  Strategies to eliminate :unknown classifications through
  conservative inference and pattern analysis.
  """

  def infer_effect(mfa, context \\ %{}) do
    strategies = [
      &try_exact_analysis/2,
      &try_pattern_matching/2,
      &try_naming_heuristics/2,
      &try_module_context/2,
      &try_arity_inference/2,
      &try_data_flow_analysis/2,
      &conservative_fallback/2
    ]

    Enum.find_value(strategies, fn strategy ->
      case strategy.(mfa, context) do
        {:ok, effect} -> {:ok, effect}
        :unknown -> nil
      end
    end) || {:ok, :s}  # Ultimate fallback: assume side effects
  end
end
```

### Inference Strategies

1. **Pattern Matching Strategy**
   ```elixir
   defp try_pattern_matching({module, function, arity}, context) do
     patterns = [
       # Getter patterns
       {~r/^get_/, :d},      # get_* often reads state
       {~r/^fetch_/, :d},    # fetch_* often reads state
       {~r/_pid$/, :d},      # *_pid functions often read process info

       # Setter patterns
       {~r/^set_/, :s},      # set_* often writes state
       {~r/^put_/, :s},      # put_* often writes state
       {~r/^update_/, :s},   # update_* often modifies
       {~r/^delete_/, :s},   # delete_* often modifies
       {~r/^send_/, :s},     # send_* does message passing

       # Pure patterns
       {~r/^is_/, :p},       # is_* predicates usually pure
       {~r/^valid/, :p},     # valid* validators usually pure
       {~r/^to_/, :p},       # to_* converters often pure
       {~r/\?$/, :p},        # trailing ? often pure predicate

       # Exception patterns
       {~r/!$/, {:e, [:dynamic]}},  # trailing ! raises on error
       {~r/^assert_/, {:e, ["Elixir.AssertionError"]}},
       {~r/^raise_/, {:e, [:dynamic]}},
       {~r/^throw_/, {:e, [:throw]}}
     ]

     function_str = to_string(function)
     Enum.find_value(patterns, fn {pattern, effect} ->
       if Regex.match?(pattern, function_str) do
         {:ok, effect}
       end
     end) || :unknown
   end
   ```

2. **Module Context Strategy**
   ```elixir
   defp try_module_context({module, _function, _arity}, _context) do
     module_str = to_string(module)

     cond do
       # I/O modules are effectful
       module in [IO, File, System] ->
         {:ok, :s}

       # Process modules are effectful
       module in [Process, Task, Agent, GenServer] ->
         {:ok, :s}

       # Pure utility modules
       module in [String, List, Enum, Map, Keyword] ->
         {:ok, :p}

       # Math is pure
       String.contains?(module_str, "Math") ->
         {:ok, :p}

       # Storage modules are stateful
       String.contains?(module_str, ["Storage", "Cache", "Repo"]) ->
         {:ok, :s}

       true ->
         :unknown
     end
   end
   ```

3. **Dynamic Dispatch Resolution**
   ```elixir
   defp try_data_flow_analysis({:apply, _, [module_expr, func_expr, args]}, context) do
     # Try to resolve module and function through data flow
     possible_modules = resolve_possible_values(module_expr, context)
     possible_functions = resolve_possible_values(func_expr, context)

     if length(possible_modules) == 1 and length(possible_functions) == 1 do
       [module] = possible_modules
       [function] = possible_functions
       arity = length(args)

       # Recursively analyze the resolved MFA
       infer_effect({module, function, arity}, context)
     else
       # Multiple possibilities - take conservative union
       effects = for m <- possible_modules, f <- possible_functions do
         infer_effect({m, f, length(args)}, context)
       end

       merge_effects(effects)
     end
   end

   defp resolve_possible_values(expr, context) do
     case expr do
       {:var, _, name} ->
         # Look up variable in context
         Map.get(context.bindings, name, [:unknown])

       module when is_atom(module) ->
         [module]

       _ ->
         [:unknown]
     end
   end
   ```

4. **Arity-Based Inference**
   ```elixir
   defp try_arity_inference({_module, _function, arity}, _context) do
     # Higher arity often indicates callbacks or handlers
     cond do
       arity == 0 ->
         # Nullary functions often read state
         {:ok, :d}

       arity >= 4 ->
         # High arity suggests complex operation
         {:ok, :s}

       true ->
         :unknown
     end
   end
   ```

5. **Conservative Fallback**
   ```elixir
   defp conservative_fallback({module, function, arity}, context) do
     # Make conservative assumptions based on all available info

     # Check if module is a behavior
     if is_behaviour?(module) do
       {:ok, :s}  # Behaviors often have effects
     else
       # Check common suffixes
       module_parts = Module.split(module)
       last_part = List.last(module_parts) || ""

       cond do
         String.ends_with?(last_part, "Server") -> {:ok, :s}
         String.ends_with?(last_part, "Supervisor") -> {:ok, :s}
         String.ends_with?(last_part, "View") -> {:ok, :p}
         String.ends_with?(last_part, "Helper") -> {:ok, :p}
         true -> {:ok, :s}  # When in doubt, assume side effects
       end
     end
   end
   ```

### Macro Expansion Improvements

```elixir
defmodule Litmus.Analyzer.MacroExpander do
  def expand_with_context(ast, env) do
    # Expand macros while preserving effect information
    expanded = Macro.expand(ast, env)

    # Tag expanded code with source macro
    tag_with_source(expanded, ast)
  end

  defp tag_with_source(expanded_ast, original_ast) do
    # Add metadata about macro origin
    # This helps track effects back to macro calls
    Macro.postwalk(expanded_ast, fn node ->
      Macro.update_meta(node, &Map.put(&1, :macro_source, original_ast))
    end)
  end
end
```

## State of Project After Implementation

### Improvements
- **Unknown classifications**: From 5-15% to <1%
- **Dynamic dispatch**: Resolved in 60% of cases
- **Missing sources**: Conservative inference instead of :unknown
- **Macro handling**: Improved with context preservation

### New Capabilities
- Pattern-based effect inference
- Module behavior detection
- Dynamic dispatch resolution
- Context-aware analysis
- Confidence scores for inferences

### Files Modified
- Created: `lib/litmus/analyzer/unknown_eliminator.ex`
- Created: `lib/litmus/analyzer/pattern_inference.ex`
- Modified: `lib/litmus/analyzer/ast_walker.ex`
- Created: `lib/litmus/analyzer/macro_expander.ex`
- Created: `test/analyzer/unknown_eliminator_test.exs`

### Classification Statistics
```elixir
# Before
%{
  pure: 2831,
  side_effects: 324,
  unknown: 412  # 15%
}

# After
%{
  pure: 2831,
  side_effects: 709,
  unknown: 27    # <1%
}
```

## Next Recommended Objective

**Objective 009: Captured Function Detection Fix**

Fix the critical bug where captured functions (&Module.function/arity) are skipped during purity analysis, allowing effects to slip through pure blocks. This is a targeted fix that will close one of the major effect leakage paths.