# PDR 004: Handling Kernel.raise to Identify Specific Error Types

## Status
Proposed

## Context
`Kernel.raise` is a special form in Elixir that can be statically analyzed to determine what specific error type is being raised. Unlike dynamic exception raising (e.g., `raise variable`), when `Kernel.raise` is called with a specific module or exception struct, we can determine the precise exception type at compile time and incorporate this information into the effect system.

## Problem Statement
The current effect analysis system treats all `raise` expressions similarly, without taking advantage of the fact that `Kernel.raise/1`, `Kernel.raise/2`, and `Kernel.raise/3` with specific exception modules can be analyzed to identify the exact exception type being raised. This means opportunities for more precise exception tracking are being missed.

### Current Limitations
- `Kernel.raise` expressions with specific exception types are not analyzed to identify the exact exception
- The system doesn't leverage the static information available from `raise` with specific exception modules
- Exception tracking is less precise than it could be by ignoring static `raise` information

### Example
```elixir
# Currently, this might just be marked as a generic exception
def validate_input(input) do
  if input == nil do
    raise ArgumentError, message: "input cannot be nil"  # Should identify ArgumentError specifically
  else
    input
  end
end

# Or this with an exception struct
def check_map(map, key) do
  unless Map.has_key?(map, key) do
    raise KeyError, key: key, term: map  # Should identify KeyError specifically
  end
  Map.get(map, key)
end
```

## Proposed Solution
Enhance the AST analysis and bidirectional inference system to extract specific exception types from `Kernel.raise` expressions by:

1. Updating the effect tracker to recognize `Kernel.raise` as a special form
2. Extracting exception module information from `raise` calls with module arguments
3. Incorporating the specific exception type into the function's effect type
4. Ensuring the bidirectional type inference system properly handles these specific exception types

### Implementation Approach
1. Modify the AST walker in `lib/litmus/analyzer/ast_walker.ex` to identify `Kernel.raise` calls and extract exception types
2. Update the effect tracker in `lib/litmus/analyzer/effect_tracker.ex` to handle specific exception identification
3. Enhance the bidirectional inference in `lib/litmus/inference/bidirectional.ex` to process these specific exception types
4. Update the type system in `lib/litmus/types/effects.ex` to properly represent and combine specific exception types
5. Add pattern matching in the analysis to distinguish between different forms of `raise`:
   - `raise Module` - identifies the specific module
   - `raise %Module{}` - identifies from the struct
   - `raise variable` - remains as unknown/dynamic exception

### Files to Modify
- `lib/litmus/analyzer/ast_walker.ex` - Update to identify specific exceptions in raise calls
- `lib/litmus/analyzer/effect_tracker.ex` - Update effect tracking for specific exceptions
- `lib/litmus/inference/bidirectional.ex` - Update inference for specific exceptions
- `lib/litmus/types/effects.ex` - Update effect type representation
- `test/litmus/` - Add tests for specific exception identification

## Alternatives Considered
1. **Conservative approach**: Only identify exceptions when they're clearly specified, treat others as generic - safer but less informative
2. **Aggressive pattern matching**: Try to infer exception types from variable content - more complex and error-prone
3. **Hybrid approach**: Full identification where possible, generic otherwise - balanced approach (chosen)

## Expected Benefits
- More precise exception tracking for functions using `Kernel.raise` with specific types
- Better developer understanding of exactly which exceptions functions may raise
- Enhanced static analysis accuracy for exception behavior
- Improved capability for tools to reason about exception handling requirements

## Risks and Mitigation
- **False positives**: Incorrectly identifying exception types - mitigate by being conservative and only identifying clear cases
- **Complexity**: Adding special case handling for raise expressions - mitigate by following existing patterns
- **Performance**: Additional analysis might impact performance - mitigate by optimizing critical paths

## Testing Strategy
- Create tests for various forms of `Kernel.raise` calls with specific exception types
- Verify correct identification of exception modules and structs
- Test edge cases where exception types cannot be determined
- Ensure backward compatibility with existing exception tracking
- Test functions that combine different forms of exception raising