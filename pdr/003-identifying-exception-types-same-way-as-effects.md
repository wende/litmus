# PDR 003: Identifying Exception Types the Same Way as Effects

## Status
Proposed

## Context
Currently, exception types are not identified with the same precision as other effect types in the Litmus system. The system should apply the same rigorous approach used for tracking side effects, dependent effects, and lambda effects to identify and track specific exception types with the same level of detail.

## Problem Statement
Exception types are currently tracked more coarsely compared to other effect types. The effect inference system needs to identify specific exception types (like `ArgumentError`, `KeyError`, `File.Error`, etc.) with the same precision as it does for other effect types like side effects (`s`), dependent effects (`d`), and lambda effects (`l`).

### Current Limitations
- Exception types are not tracked with the same granularity as other effect types
- The system doesn't leverage the same sophisticated analysis for exception type identification
- Specific exception types are not treated as first-class effect entities in the inference system
- Limited ability to distinguish between different types of exceptions that functions may raise

### Example
```elixir
# Currently, all exceptions might be grouped together, but we want:
def handle_exception_cases(data) do
  case data do
    %{} -> Map.fetch!(data, :key)  # Should identify KeyError specifically
    _ -> raise ArgumentError       # Should identify ArgumentError specifically
  end
end
```

## Proposed Solution
Apply the same rigorous type inference methodology used for other effect types to exception type identification by:

1. Integrating specific exception type tracking into the bidirectional type inference system
2. Creating a taxonomy of exception types similar to other effect classifications
3. Enhancing the AST analysis to identify specific exception types from `raise` expressions
4. Updating the effect unification and substitution systems to properly handle exception types

### Implementation Approach
1. Extend the bidirectional inference in `lib/litmus/inference/bidirectional.ex` to track specific exception types
2. Update the effect type system in `lib/litmus/types/effects.ex` to include detailed exception type information
3. Modify the AST walker in `lib/litmus/analyzer/ast_walker.ex` to identify specific exception modules in `raise` expressions
4. Enhance type unification in `lib/litmus/types/unification.ex` to handle exception type constraints
5. Update the substitution mechanism in `lib/litmus/types/substitution.ex` to work with exception types
6. Modify the registry system to store specific exception type information for standard library functions

### Files to Modify
- `lib/litmus/inference/bidirectional.ex` - Update inference for specific exception types
- `lib/litmus/types/effects.ex` - Extend effect types to include exception taxonomy
- `lib/litmus/analyzer/ast_walker.ex` - Update to identify specific exception types
- `lib/litmus/types/unification.ex` - Update unification for exception types
- `lib/litmus/types/substitution.ex` - Update substitution for exception types
- `.effects.json` - Update registry with specific exception types

## Alternatives Considered
1. **Exception hierarchies**: Create inheritance-based exception tracking - more complex but more expressive
2. **Tag-based exceptions**: Use simple tags for exception types - simpler but less structured
3. **Modular exception system**: Separate exception tracking from main effect system - cleaner separation but less integrated

## Expected Benefits
- More precise tracking of specific exception types rather than generic exception effects
- Better developer understanding of what specific exceptions can be raised
- Enhanced static analysis capabilities for exception handling
- Consistent treatment of exception types with other effect types in the system

## Risks and Mitigation
- **Complexity**: Adding detailed exception tracking increases system complexity - mitigate by following existing patterns used for other effects
- **Performance**: More detailed exception analysis might impact performance - mitigate through optimization
- **Compatibility**: Changes to effect type representations might affect existing code - mitigate by maintaining backward compatibility

## Testing Strategy
- Create tests for functions that raise specific exception types
- Verify correct identification of different exception types
- Test exception type propagation through function calls
- Ensure backward compatibility with existing exception tracking
- Test integration with existing effect type systems