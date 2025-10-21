# PDR 004: Handling Kernel.raise to Identify Specific Error Types

## Status
✅ **Fully Implemented** - 2025-10-21 (Initial) | Updated 2025-10-21 (Format Migration Complete)

## Implementation Summary
The bidirectional inference system now successfully extracts specific exception types from `Kernel.raise` expressions and tracks them through the effect system. The implementation handles both pre-expansion (`raise ArgumentError, "msg"`) and post-expansion (`:erlang.error(ArgumentError.exception("msg"))`) forms. The old `:exn` atom format has been completely replaced with the new `{:e, [exception_modules]}` tuple format throughout the codebase, with comprehensive stdlib coverage for Kernel functions.

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

## Implementation Details

### Files Modified
1. **`lib/litmus/inference/bidirectional.ex`** - Added exception extraction logic
   - `extract_exception_from_raise/1` - Extracts exception types from pre-expansion raise AST
   - `extract_exception_from_erlang_error/1` - Handles post-expansion `:erlang.error` calls
   - `extract_exception_from_struct/1` - Extracts module from struct expressions
   - Special case handling in `synthesize_call/2` for `:erlang.error/1,3`

2. **`lib/litmus/formatter.ex`** - Enhanced exception formatting
   - `format_exception_types/1` - Pretty prints exception type lists
   - `format_exception_name/1` - Formats individual exception names
   - Smart filtering removes generic `:exn` when specific types present
   - Output format: `⟨exn:ArgumentError | exn:KeyError⟩`

3. **`lib/litmus/types/core.ex`** - Effect combining improvements
   - Updated `to_compact_effect/1` to handle `{:e, list}` with deduplication
   - Better combining of multiple exception effects

4. **`lib/litmus/types/effects.ex`** - Exception effect operations
   - `combine_effects/2` for `{:e, list}` types with union and deduplication
   - `extract_exception_types/1` - Extracts all exception types from an effect
   - Row polymorphism support for exception effects

### Supported Patterns

✅ **Working**:
```elixir
# Module with message
raise ArgumentError, "message"
# => {:e, ["Elixir.ArgumentError"]}

# Struct literal
raise %ArgumentError{message: "msg"}
# => {:e, ["Elixir.ArgumentError"]}

# String (defaults to RuntimeError)
raise "error message"
# => {:e, ["Elixir.RuntimeError"]}

# Multiple exception types (if/else branches)
if condition do
  raise ArgumentError
else
  raise KeyError
end
# => {:e, ["Elixir.ArgumentError", "Elixir.KeyError"]}

# Dynamic exception
raise variable
# => {:e, [:dynamic]}

# Post-expansion :erlang.error
ArgumentError.exception("msg")
# => {:e, ["Elixir.ArgumentError"]}
```

### Test Coverage
- ✅ `test/infer/edge_cases_analysis_test.exs` - Updated to expect specific ArgumentError
- ✅ `test/infer/infer_analysis_test.exs` - Added dynamic exception tracking test
- ✅ `test/infer/regression_analysis_test.exs` - Updated for ArgumentError and RuntimeError
- ✅ `test/infer/lambda_exception_test.exs` - Lambda exception propagation tests (4 tests)
- ✅ `test/infer/exception_edge_cases_analysis_test.exs` - Comprehensive edge cases (31 tests)
- ✅ `test/support/exception_edge_cases_test.exs` - 40+ edge case functions
- ✅ All 605 tests passing (100%)

### Effect Representation
```elixir
# Effect type format
{:e, [exception_modules]}

# Examples
{:e, ["Elixir.ArgumentError"]}                      # Single specific exception
{:e, ["Elixir.ArgumentError", "Elixir.KeyError"]}   # Multiple exceptions
{:e, [:dynamic]}                                     # Runtime-determined
{:e, [:exn]}                                         # Generic (fallback)
```

### Formatter Output
```bash
$ mix effect lib/my_module.ex

validate!/1
  Effects: ⟨exn:ArgumentError⟩
  Calls: ⚠ Kernel.raise/2

process!/1
  Effects: ⟨exn:ArgumentError | exn:KeyError⟩
  Calls: ⚠ Kernel.raise/2 (multiple branches)
```

## Verification

The implementation successfully achieves all proposed goals:
- ✅ Identifies specific exception types from `Kernel.raise` expressions
- ✅ Handles both pre-expansion and post-expansion forms
- ✅ Tracks dynamic exceptions with `:dynamic` marker
- ✅ Integrates with row-polymorphic effect system
- ✅ Pretty-prints exception types in output
- ✅ All tests passing with updated expectations

## Final Statistics (2025-10-21)

**Format Migration**: Old `:exn` atom completely replaced with `{:e, [types]}` tuple

**Exception Type Coverage in Stdlib**:
- 10 Kernel functions with specific types (ArgumentError, ArithmeticError, BadMapError, etc.)
- 2 functions with generic `:exn` (Mix.raise - correctly dynamic)
- 5x improvement from initial 2 functions to 10 functions

**Specific Types Tracked**:
```elixir
# Kernel module (.effects.explicit.json)
"div/2": {"e": ["ArithmeticError"]}
"hd/1": {"e": ["ArgumentError"]}
"tl/1": {"e": ["ArgumentError"]}
"binary_part/3": {"e": ["ArgumentError"]}
"bit_size/1": {"e": ["ArgumentError"]}
"byte_size/1": {"e": ["ArgumentError"]}
"elem/2": {"e": ["ArgumentError"]}
"map_size/1": {"e": ["BadMapError"]}
"put_elem/3": {"e": ["ArgumentError"]}
"tuple_size/1": {"e": ["ArgumentError"]}
```

**Key Fixes**:
1. **Lambda Exception Propagation**: Fixed `:unknown` effect pollution when exceptions raised in lambdas passed to `Enum.map/2`, `Enum.filter/2`, etc. by skipping argument synthesis for `:erlang.error` calls
2. **Registry Reading**: Fixed `effect_type/1` to return `{:e, types}` instead of converting to `:exn`, with "Elixir." prefix normalization
3. **Format Normalization**: All exception effects now use consistent `{:e, [module_names]}` format
4. **Fallback Consistency**: Changed fallback from `{:effect_label, :exn}` to `{:e, [:exn]}` for unknown exceptions

**Test Results**: ✅ 605 tests passing, 0 failures

## Related PRDs
- See `docs/EXCEPTION_TRACKING_PLAN.md` for overall exception tracking roadmap
- PDR 003: Identifying Exception Types Same Way as Effects (parent PDR)
- PDR 002: Functions Returning Exception and Side Effects (related)