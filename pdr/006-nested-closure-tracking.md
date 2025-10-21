# PDR 006: Nested Closure Tracking - Functions Returning Functions with Effects

## Status
🔄 **Proposed** - 2025-10-21

## Context
Currently, Litmus can analyze lambda effects for first-order functions (functions that take lambdas as arguments), but cannot track effects through nested closures where functions return other functions. This is a significant gap for functional programming patterns that are common in Elixir.

## Problem Statement
The current system cannot properly track effects through nested closures where functions return functions that themselves have effects. This means analyzing code like higher-order factory functions, decorators, and functional composition patterns fails to properly characterize the effects.

### Current Limitations
- **No return type analysis** - Functions that return closures are not analyzed for what effects those closures might have
- **Closure effect propagation** - Effects from captured variables in nested closures are not tracked
- **Partial application** - Functions that partially apply other functions with effects lose effect information
- **Decorator patterns** - Cannot properly track effects through decorator/wrapper functions

### Example 1: Simple Closure Return
```elixir
# Current: Effect is unknown/incomplete
# Should track: The returned function has `:s` (side effects)
def make_logger(target) do
  fn message ->
    IO.puts("#{target}: #{message}")  # Side effect!
  end
end

# Calling the returned function should show it has side effects
logger = make_logger("MyApp")
logger.("Hello")  # Should know this has side effects
```

### Example 2: Nested Closures with Multiple Effects
```elixir
# Current: Inner effects are not tracked through the return
# Should track: Both the intermediate function and final result have effects
def pipeline_builder(transform) do
  fn data ->
    result = transform.(data)  # Effect depends on transform
    File.write!("output.txt", result)  # Side effect!
    result
  end
end
```

### Example 3: Effect Accumulation in Closures
```elixir
# Current: Cannot properly characterize the returned function's effects
# Should track: The returned function has both dependent and side effects
def create_validator(validator_fn) do
  fn input ->
    if valid?(input, validator_fn) do  # Depends on validator_fn
      File.write!("validated.txt", input)  # Side effect
      :ok
    else
      :error
    end
  end
end
```

### Example 4: Multiple Levels of Nesting
```elixir
# Current: Fails to track through multiple levels
# Should track: Function returns a function that returns a function with effects
def make_async_processor(service) do
  fn command ->
    fn data ->
      result = service.process(data)  # Effect depends on service
      IO.puts("Result: #{result}")    # Side effect
      result
    end
  end
end
```

## Proposed Solution
Enhance the bidirectional type inference system to:

1. **Analyze function return types** - When a function returns a closure, analyze what effects that closure has
2. **Capture closure effects** - Track effects from variables captured in the closure scope
3. **Propagate effects through nesting** - Properly combine effects from multiple levels of nesting
4. **Handle variable dependencies** - Track which parameters affect the closure's effects

### Implementation Approach

#### Phase 1: Return Type Analysis
1. Extend `synthesize/3` in `lib/litmus/inference/bidirectional.ex` to handle `:fn` expressions in return position
2. When analyzing a function body that returns a closure, analyze the closure's effect
3. Store the return closure's effect as part of the function's type information

#### Phase 2: Closure Effect Tracking
1. Modify `effect_tracker.ex` to track effects within closures
2. When analyzing a closure, capture:
   - Direct effects (calls to effectful functions)
   - Inherited effects (from parameters and captured variables)
   - Dependencies (parameters that affect effects)
3. Create a "closure effect" abstraction that distinguishes from regular `:l` (lambda) effects

#### Phase 3: Effect Propagation
1. Update `combine_effects/2` to handle closure returns
2. When a function returns a closure with known effects, propagate those effects appropriately
3. Distinguish between:
   - Effects the closure *will* have when called (conditional on runtime)
   - Effects the returning function has (setup/closure creation)

#### Phase 4: AST Walker Integration
1. Extend `lib/litmus/analyzer/ast_walker.ex` to handle closure return tracking
2. Add analysis for functions that return functions in cross-module analysis
3. Update the `AnalysisResult` to include closure return type information

### Implementation Details

**Data Structure for Closure Returns**:
```elixir
# New type in lib/litmus/types/core.ex
{:closure, effect, params}
# Where:
# - effect: The effect the closure will have when called
# - params: List of parameter names that affect the effect
#
# Example: {:closure, {:s, ["IO.puts/1"]}, ["message", "target"]}
```

**Modified Synthesize for Fn Expressions**:
```elixir
# In bidirectional.ex, for fn expressions:
# 1. Analyze the closure body with parameter types
# 2. Capture effects from the body
# 3. Return {:closure, effects, param_names} for return position analysis
```

**Closure Effect in Call Tracking**:
```elixir
# When calling a variable that holds a closure:
# 1. Look up the closure's effect type
# 2. Substitute captured variables with their actual effects
# 3. Combine with the calling context's effects
```

### Files to Modify
- **`lib/litmus/types/core.ex`** - Add `:closure` effect type, update `to_compact_effect/1`
- **`lib/litmus/inference/bidirectional.ex`** - Extend `synthesize/3` for `:fn` expressions, add closure analysis
- **`lib/litmus/analyzer/ast_walker.ex`** - Track closure return types, update effect extraction
- **`lib/litmus/analyzer/effect_tracker.ex`** - Add closure effect tracking
- **`lib/litmus/types/effects.ex`** - Update `combine_effects/2` for closure propagation
- **Test files** - Add comprehensive tests for nested closures

### Example Implementation Flow
```elixir
# For this code:
def make_logger(target) do
  fn message -> IO.puts("#{target}: #{message}") end
end

# Analysis flow:
# 1. synthesize(:make_logger, ...)
# 2. Analyze body -> returns :fn expression
# 3. Analyze :fn expression body
# 4. Find IO.puts/1 call (side effect)
# 5. Capture parameter: "message", captured: "target"
# 6. Return: {:closure, {:s, ["IO.puts/1"]}, ["message", "target"]}
# 7. make_logger effect: :p (pure - just creates closure)
# 8. When logger.(msg) is called -> know it has :s effect
```

## Alternatives Considered

1. **Runtime effect tracking only** - Defer all closure analysis to runtime - loses static analysis benefits, defeats the purpose of Litmus

2. **Single-level closure support** - Only support direct closures, not nested returns - simpler but incomplete, doesn't handle real patterns

3. **Conservative over-reporting** - Mark all closures as unknown effects - safe but provides no useful information

4. **Separate closure analysis pass** - Create a distinct pre-pass for closures - more complex but could be cleaner

## Expected Benefits

- **Functional programming patterns** - Properly analyze common Elixir patterns like factory functions, decorators, currying
- **Better documentation** - Static analysis can now document what effects a returned function will have
- **Safer abstractions** - Developers can create effect-safe abstractions using closures
- **More precise pure analysis** - Can distinguish between "returns a pure function" vs "returns an effectful function"
- **Pipeline composition** - Better support for functional composition patterns with effect tracking

## Risks and Mitigation

- **Complexity increase** - Closure tracking adds significant complexity to the type system
  - *Mitigation*: Implement in phases, maintain clear separation of concerns, add comprehensive documentation

- **Performance impact** - Analyzing nested closures could slow down analysis
  - *Mitigation*: Optimize closure caching, limit analysis depth for highly nested structures, benchmark carefully

- **False positives** - May over-report effects from closures due to conservative analysis
  - *Mitigation*: Start conservative, add heuristics to refine based on test feedback

- **Integration challenges** - May conflict with existing lambda effect tracking
  - *Mitigation*: Clearly distinguish `:l` (higher-order function parameter) from `:closure` (returned closure)

## Testing Strategy

### Phase 1: Basic Closure Return Tests
```elixir
# Test that closures returned from functions have tracked effects
test "simple closure return with side effects" do
  # make_logger returns a closure with {:s, ["IO.puts/1"]}
end

test "closure return with pure effects" do
  # Factory returning pure function
end

test "closure return with multiple effects" do
  # Factory returning function with combined effects
end
```

### Phase 2: Parameter Dependency Tests
```elixir
test "closure captures parameters with effects" do
  # Closure inherits effects from parameters
end

test "conditional closure effects" do
  # Closure effects depend on parameter types
end
```

### Phase 3: Nesting Tests
```elixir
test "two-level closure nesting" do
  # Function returns function that returns function
end

test "deeply nested closures" do
  # Test practical depth limits
end

test "mutually dependent closures" do
  # Multiple closures capturing each other
end
```

### Phase 4: Integration Tests
```elixir
test "closure in Enum.map" do
  # make_logger |> Enum.map() should track closure effects
end

test "closure returned from higher-order function" do
  # Functions like filter_builder returning closures
end

test "closure with captured side effects" do
  # Closure that captures a variable holding an effectful function
end
```

### Phase 5: Edge Cases
```elixir
test "anonymous closure without explicit return" do
  # Implicit closure from last expression
end

test "closure escaping function scope" do
  # Variables captured across scope boundaries
end

test "recursive closure" do
  # Closure that calls itself
end

test "closure with pattern matching" do
  # Closure parameters with patterns
end
```

## Success Criteria

- [ ] Can analyze functions that return closures with effects
- [ ] Closure effects are properly tracked through nesting (at least 2 levels)
- [ ] Parameter capture is correctly analyzed
- [ ] All new tests pass
- [ ] No regression in existing tests
- [ ] Documentation updated with closure examples
- [ ] Performance remains acceptable for real codebases

## Related PDRs
- PDR 001: Returning Many Effect Types (closely related, handles multiple effect types)
- PDR 002: Functions Returning Exception and Side Effect Types (similar multi-effect handling)

## Notes
- This feature enables proper analysis of functional programming patterns
- Should integrate cleanly with existing lambda tracking
- May benefit from dedicated debug output (like current effect trace)
- Consider caching closure effects to avoid re-analysis
