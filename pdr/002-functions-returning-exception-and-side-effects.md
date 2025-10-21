# PDR 002: Functions Returning Both Exception and Side Effect Types

## Status
✅ **Implemented** - 2025-10-21

## Context
Currently, functions like `File.write!/2` that can both raise exceptions and perform side effects are not properly represented in the effect system. The system needs to handle cases where a single function can have multiple distinct effect types simultaneously, specifically both exception effects and side effects.

## Problem Statement
The current effect system cannot properly represent functions that simultaneously raise exceptions and perform side effects. For functions like `File.write!/2`, the system needs to capture both that it can raise exceptions (like `File.Error`) and that it performs side effects (the actual file write operation).

### Current Limitations
- Functions that both raise exceptions and perform side effects are not fully characterized
- The effect system only captures one aspect of such functions' behavior
- Developers don't get complete information about all possible behaviors of functions

### Example
```elixir
# File.write!/2 should be represented as having both:
# - Exception effects (can raise File.Error)
# - Side effects (writes to filesystem)
def save_data(file_path, data) do
  File.write!(file_path, data)  # This has both exception and side effects
end
```

## Proposed Solution
Enhance the effect type system to allow functions to be classified with both exception and side effect types simultaneously by:

1. Updating the effect type representation to support combined effects
2. Modifying the function analysis to detect both exception-raising and side-effect behavior
3. Ensuring the bidirectional inference system tracks both types of effects
4. Updating the registry system to store combined effect information

### Implementation Approach
1. Modify the effect type representation in `lib/litmus/types/effects.ex` to allow multiple effect classifications per function
2. Update the AST analysis in `lib/litmus/analyzer/effect_tracker.ex` to identify both exception and side effect behaviors
3. Enhance the bidirectional inference in `lib/litmus/inference/bidirectional.ex` to accumulate both effect types
4. Update the `.effects.json` registry format to allow storing combined effects
5. Adjust the display functions in `lib/litmus/types/core.ex` to show combined effects clearly

### Files to Modify
- `lib/litmus/types/effects.ex` - Update effect type structure
- `lib/litmus/analyzer/effect_tracker.ex` - Update effect detection
- `lib/litmus/inference/bidirectional.ex` - Update inference for combined effects
- `.effects.json` - Update registry format for combined effects
- `lib/litmus/types/core.ex` - Update effect display

## Alternatives Considered
1. **Primary effect priority**: Consider one type of effect as primary, the other as secondary - loses important information
2. **Separate effect tracking systems**: Maintain separate exception and side effect tracking - adds complexity but keeps concerns separate
3. **Effect hierarchies**: Create a hierarchy where one effect type encompasses others - might oversimplify

## Expected Benefits
- More complete representation of functions that have multiple types of effects
- Better information for developers about the full behavior profile of functions
- Improved static analysis accuracy for complex functions
- Enhanced capability for tools to understand and reason about function behavior

## Risks and Mitigation
- **Complexity**: Combined effects may make the system more complex - mitigate by maintaining clear documentation
- **Performance**: More complex effect tracking might impact analysis speed - mitigate by optimizing critical paths
- **Comprehension**: Developers might find combined effects harder to understand - mitigate by clear documentation and examples

## Testing Strategy
- Create tests for functions with both exception and side effects (like File.write!/2)
- Verify proper identification of combined effects
- Test functions that have multiple effect types in different combinations
- Ensure backward compatibility with existing single-effect functions
- Test edge cases where effects interact in complex ways