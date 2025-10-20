# PDR 001: Returning Many Effect Types

## Status
Proposed

## Context
Currently, the effect system only allows functions to return a single type of effect. However, there are cases where functions can have multiple different effect types simultaneously. The current system cannot properly represent functions that have multiple effect types such as exception effects, dependent effects, and side effects all at once.

## Problem Statement
The current effect type system cannot represent functions that return multiple distinct effect types. For example, a function should be able to return a combination like `[{e, [Elixir.ArgumentError]}, {d, [Process.alive?/1]}, {s, [File.write/2]}]` to indicate it has exception effects (ArgumentError), dependent effects (Process.alive?/1), and side effects (File.write/2).

### Current Limitations
- Functions that combine multiple effect types are not properly represented
- The effect system is unable to provide comprehensive information about all possible effects a function may have
- Developers cannot get complete information about what effects to expect from a function

### Example
```elixir
# This function has multiple effects that should be tracked separately:
# - Exception effects (ArgumentError)
# - Dependent effects (Process.alive?/1) 
# - Side effects (File.write/2)
def complex_function(data) do
  if Process.alive?(pid) do
    File.write("output.txt", data)
  else
    raise ArgumentError, "process not alive"
  end
end
```

## Proposed Solution
Enhance the effect type system to support functions that return multiple effect types simultaneously by:

1. Modifying the effect type representation to be a list of effect types instead of a single type
2. Updating the type inference system to accumulate multiple effects during analysis
3. Adjusting the display and API functions to properly show multiple effects
4. Ensuring backward compatibility with existing effect type usage

### Implementation Approach
1. Modify the effect type structure in `lib/litmus/types/effects.ex` to support multiple effect types
2. Update the bidirectional inference system in `lib/litmus/inference/bidirectional.ex` to collect multiple effects
3. Update the effect analysis to properly track multiple effect types through function calls
4. Adjust display functions in `lib/litmus/types/core.ex` to show combined effects properly
5. Ensure all existing functionality remains compatible with the new multi-effect system

### Files to Modify
- `lib/litmus/types/effects.ex` - Update effect type structure
- `lib/litmus/inference/bidirectional.ex` - Update inference to collect multiple effects
- `lib/litmus/types/core.ex` - Update display functions
- Possibly `lib/litmus/analyzer/ast_walker.ex` - Update effect tracking

## Alternatives Considered
1. **Union types**: Create union types for different combinations - more complex but potentially more restrictive
2. **Single combined effect**: Create a single super-effect that encompasses all - loses granularity
3. **Multiple separate effect systems**: Keep separate tracking - adds complexity but maintains clarity

## Expected Benefits
- More accurate representation of functions with multiple effects
- Better information for developers about all possible effects of functions
- Enhanced capability for static analysis tools to understand complex function behavior
- Improved precision in effect tracking across the system

## Risks and Mitigation
- **Complexity**: Multiple effects may make the system more complex to understand - mitigate by maintaining clear documentation and backward compatibility
- **Performance**: More complex effect tracking might impact performance - mitigate by optimizing critical paths
- **API Changes**: Breaking changes might be needed - mitigate by ensuring backward compatibility where possible

## Testing Strategy
- Create tests for functions with multiple effect types
- Verify backward compatibility with existing single-effect functions
- Ensure all combinations of effects are properly tracked and represented
- Test edge cases where many different effect types are present