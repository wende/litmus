# PDR 005: Try..Catch Removing Exceptions from Scope

## Status
Proposed

## Context
In Elixir, `try..catch` blocks are used to handle exceptions, and properly handled exceptions should not propagate to the function's overall effect type. The effect inference system needs to understand that exceptions caught within `try..catch` blocks are handled and should not be included in the function's overall exception effect signature.

## Problem Statement
Currently, the effect inference system doesn't recognize that `try..catch` blocks suppress or handle exceptions, so exceptions that are caught and handled within these blocks are still counted as unhandled exceptions for the function. This results in over-reporting of exception effects, making functions appear to raise more exceptions than they actually do from an external perspective.

### Current Limitations
- Exceptions caught and handled in `try..catch` blocks are still included in function effect types
- The system doesn't understand exception handling scope within try expressions
- Functions with proper exception handling still show caught exceptions as effects
- This leads to less precise and less useful effect analysis

### Example
```elixir
# Currently, this might show that the function can raise KeyError, 
# but with proper try..catch handling, it should not
def safe_fetch(map, key) do
  try do
    Map.fetch!(map, key)  # KeyError would be raised here
  catch
    :error, %KeyError{} -> nil  # KeyError is handled here, should not be in function's effect type
  end
end
```

## Proposed Solution
Enhance the effect inference system to recognize that exceptions caught within `try..catch` blocks are handled and should not be propagated to the function's overall exception effect type by:

1. Updating the AST analysis to identify try expressions and their catch clauses
2. Tracking which exceptions are caught and handled in different scopes
3. Removing handled exceptions from the function's overall effect signature
4. Preserving information about exceptions that are not fully handled

### Implementation Approach
1. Modify the AST walker in `lib/litmus/analyzer/ast_walker.ex` to identify try expressions and catch clauses
2. Update the effect tracker in `lib/litmus/analyzer/effect_tracker.ex` to maintain exception handling context
3. Enhance the bidirectional inference in `lib/litmus/inference/bidirectional.ex` to account for exception handling scope
4. Update the effect combination logic to subtract handled exceptions from the overall effect set
5. Ensure the system still tracks exceptions that are re-raised, transformed, or only partially handled
6. Handle complex cases like nested try expressions and rescue clauses

### Files to Modify
- `lib/litmus/analyzer/ast_walker.ex` - Update to identify try/catch expressions
- `lib/litmus/analyzer/effect_tracker.ex` - Update to track exception handling context
- `lib/litmus/inference/bidirectional.ex` - Update inference for exception handling
- `lib/litmus/types/effects.ex` - Update effect combination to handle exception subtraction
- `test/litmus/` - Add tests for try/catch exception handling

## Alternatives Considered
1. **Conservative approach**: Don't change current behavior, keep all exceptions - loses the benefit of exception handling information
2. **Simple catch-all**: Remove all exceptions in try blocks - might incorrectly remove unhandled exceptions
3. **Pattern matching approach**: Analyze catch patterns to determine exactly which exceptions are handled - most accurate (chosen)

## Expected Benefits
- More accurate exception tracking that reflects actual function behavior
- Functions with proper exception handling will have cleaner effect signatures
- Better developer experience with more precise effect information
- Enhanced capability for tools to understand true exception behavior of functions

## Risks and Mitigation
- **False negatives**: Missing exceptions that aren't actually handled - mitigate by careful analysis of catch patterns
- **Complexity**: Try/catch analysis adds significant complexity to the system - mitigate by following systematic approach
- **Performance**: Additional analysis might impact performance - mitigate by optimizing critical paths
- **Edge cases**: Complex nested try/catch scenarios - mitigate by thorough testing

## Testing Strategy
- Create tests for basic try/catch scenarios with specific exceptions
- Test nested try/catch expressions
- Verify that unhandled exceptions are still properly tracked
- Test cases where exceptions are re-raised after catching
- Test functions that combine try/catch with other exception-raising code
- Ensure backward compatibility with existing functionality