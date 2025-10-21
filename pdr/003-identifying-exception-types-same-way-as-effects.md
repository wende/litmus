# PDR 003: Identifying Exception Types the Same Way as Effects

## Status
✅ **Fully Implemented** - 2025-10-21 (Initial) | Updated 2025-10-21 (Format Migration Complete)

## Implementation Summary
Exception types are now tracked with the same precision as other effect types. The old `:exn` atom format has been completely replaced with the new `{:e, [exception_modules]}` tuple format throughout the codebase. The system properly handles exception type inference from AST, propagates exceptions through lambda expressions, and maintains specific exception types (ArgumentError, ArithmeticError, BadMapError, etc.) in the stdlib registry.

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

## Implementation Details

### Exception Type Representation
Exception types now use the same effect format as other effects:

```elixir
# Single effect type (pure, side effect, etc.)
:p                              # Pure
{:s, ["io", "file"]}           # Side effects

# Exception effects - same pattern
{:e, ["Elixir.ArgumentError"]}              # Single exception type
{:e, ["Elixir.ArgumentError", "Elixir.KeyError"]}  # Multiple exception types
{:e, [:dynamic]}                            # Dynamic exception

# Row polymorphism - exceptions integrate naturally
{:effect_row, {:e, ["Elixir.ArgumentError"]}, {:effect_label, :io}}
# => ⟨exn:ArgumentError | io⟩
```

### Integration with Effect System

1. **Effect Combining** (`lib/litmus/types/effects.ex`):
   ```elixir
   def combine_effects({:e, list1}, {:e, list2}) do
     {:e, Enum.uniq(list1 ++ list2)}
   end
   ```

2. **Effect Extraction**:
   ```elixir
   def extract_exception_types({:e, types}), do: types
   def extract_exception_types({:effect_row, {:e, types}, tail}) do
     types ++ extract_exception_types(tail)
   end
   ```

3. **Type System Integration** (`lib/litmus/types/core.ex`):
   - Exception effects participate in effect unification
   - `to_compact_effect/1` properly handles `{:e, list}` format
   - Deduplication of exception types during combining

### Formatter Integration

Exceptions are formatted consistently with other effects:

```bash
# Compact notation
e (exn:ArgumentError, exn:KeyError)

# Row notation
⟨exn:ArgumentError | exn:KeyError⟩

# Mixed effects
⟨exn:ArgumentError | io | file⟩
```

### Files Modified
- ✅ `lib/litmus/types/effects.ex` - Exception effect operations
- ✅ `lib/litmus/types/core.ex` - Effect combining with deduplication
- ✅ `lib/litmus/formatter.ex` - Exception type formatting
- ✅ `lib/litmus/inference/bidirectional.ex` - Exception inference

### Test Coverage
- ✅ Exception types tracked with same precision as other effects
- ✅ Multiple exception types combine correctly
- ✅ Row polymorphism works with exception effects
- ✅ Lambda exception propagation through higher-order functions
- ✅ All 605 tests passing (100%)

## Verification

The implementation successfully achieves parity between exception types and other effect types:
- ✅ Same representation format as other effect types
- ✅ Seamless integration with row-polymorphic effect system
- ✅ Proper combining and deduplication
- ✅ Consistent formatting and display
- ✅ First-class treatment in the type system

## Final Statistics (2025-10-21)

**Format Migration**: Old `:exn` atom completely replaced with `{:e, [types]}` tuple

**Exception Type Coverage**:
- 10 Kernel functions with specific types (ArgumentError, ArithmeticError, BadMapError)
- 2 functions with generic `:exn` (Mix.raise - correctly dynamic)
- 5x improvement from initial 2 functions to 10 functions

**Key Fixes**:
1. **Lambda Exception Propagation**: Fixed `:unknown` effect pollution when exceptions raised in lambdas passed to `Enum.map/2`, `Enum.filter/2`, etc.
2. **Registry Reading**: Fixed `effect_type/1` to return `{:e, types}` instead of converting to `:exn`
3. **Format Normalization**: Added "Elixir." prefix handling for consistent module naming
4. **Fallback Consistency**: Changed fallback to use `{:e, [:exn]}` instead of `{:effect_label, :exn}`

**Test Results**: ✅ 605 tests passing, 0 failures

## Related PRDs
- PDR 004: Handling Kernel.raise to Identify Specific Errors (implementation details)
- See `docs/EXCEPTION_TRACKING_PLAN.md` for overall roadmap