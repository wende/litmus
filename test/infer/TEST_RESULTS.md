# Effect Inference Test Results

## Summary

Successfully created comprehensive test suite covering:
- **36 functions** in `infer_test.exs` (original tests)
- **45+ functions** in `edge_cases_test.exs` (edge cases)
- **24 functions** in `regression_test.exs` (bug fixes)

## Test Coverage

### Feature Coverage

✅ **Lambda Effect Propagation**
- Pure lambdas in higher-order functions → Pure result
- Effectful lambdas in higher-order functions → Effectful result
- Nested lambdas with mixed effects → Correct effect combination

✅ **Lambda-Dependent Functions**
- Functions taking function parameters → Classified as `λ` (lambda-dependent)
- Cross-module calls to lambda-dependent functions → Show `λ` indicator
- Calling lambda-dependent with pure lambda → Pure result
- Calling lambda-dependent with effectful lambda → Effectful result

✅ **Block Expressions**
- Multi-statement blocks → Combine all effects
- Pure blocks → Pure result
- Mixed effect blocks → Effectful result
- Exception in blocks → Exception propagates

✅ **Exception Handling**
- Explicit `raise` statements → Exception effect
- Stdlib exceptions (hd, div) → Exception effect
- Module aliases in raise → No effect variables
- Nested exceptions → Propagate correctly

✅ **Effect Categories**
- Pure (`p`) - 11 functions in infer_test
- Lambda-dependent (`l`) - Correctly classified
- Context-dependent (`d`) - Process.get, System.system_time, ETS
- Unknown (`u`) - apply, runtime calls
- Exception (`e`) - 3 functions in infer_test
- Effectful (`s`) - 15 functions in infer_test

✅ **Cross-Module Analysis**
- Pure cross-module calls → `→` indicator
- Effectful cross-module calls → `⚡` indicator
- Exception cross-module calls → `⚠` indicator
- Lambda-dependent cross-module calls → `λ` indicator

✅ **Advanced Features**
- String interpolation → Pure (unless contains effects)
- Function capture → Extracts captured function effects
- Pipe operators → Propagates effects through pipeline
- If/Case expressions → Combines branch effects
- Nested higher-order functions → Multiple levels work correctly

## Regression Tests

### Bug #1: Higher-Order Functions ✅ FIXED
**Before**: `def foo(func), do: func.(10)` → `? Unknown`
**After**: `def foo(func), do: func.(10)` → `λ Lambda-dependent`

### Bug #2: Block Expressions ✅ FIXED
**Before**: `IO.puts(x); File.write!(y)` → `? Unknown`
**After**: `IO.puts(x); File.write!(y)` → `⚡ Effectful`

### Bug #3: Variables with Context ✅ FIXED
**Before**: Variables like `{name, _, Elixir}` not recognized
**After**: All variable forms recognized correctly

### Bug #4: Exception Functions ✅ FIXED
**Before**: `raise ArgumentError` → `? Unknown`
**After**: `raise ArgumentError` → `⚠ Exception`

### Bug #5: Apply Function ✅ FIXED
**Before**: `apply(IO, :puts, [...])` → `⚡ Effectful`
**After**: `apply(IO, :puts, [...])` → `? Unknown`

### Bug #6: Cross-Module Indicators ✅ FIXED
**Before**: Lambda-dependent calls showed `?`
**After**: Lambda-dependent calls show `λ`

### Bug #7: Test Support Discovery ✅ FIXED
**Before**: test/support only included in test env
**After**: test/support always included if exists

### Bug #8: Enum.reduce ✅ FIXED
**Before**: `Enum.reduce/3` → `? Unknown`
**After**: `Enum.reduce/3` → `λ Lambda-dependent`

## Sample Results

### Pure Functions
```
✓ Pure: map_with_pure_lambda/1
✓ Pure: reduce_with_pure_lambda/1
✓ Pure: pure_arithmetic/2
✓ Pure: pure_string_ops/1
```

### Lambda-Dependent Functions
```
λ Lambda-dependent: higher_order_pure/1
λ Lambda-dependent: higher_order_two_funcs/2
Call indicators show: λ Enum.reduce/3
```

### Effectful Functions
```
⚡ Effectful: map_with_io_lambda/1
⚡ Effectful: write_to_file/2
⚡ Effectful: log_and_save/2 (was Bug #2)
```

### Exception Functions
```
⚠ Exception: may_raise_list_error/1
⚠ Exception: exception_explicit_raise/0 (was Bug #4)
⚠ Exception: exception_division/2
```

### Unknown Functions
```
? Unknown: unknown_apply_kernel/0 (was Bug #5)
? Unknown: unknown_apply_3/3
```

### Context-Dependent Functions
```
◐ Context-dependent: dependent_process_get/1
◐ Context-dependent: dependent_system_time/0
◐ Context-dependent: dependent_ets_lookup/2
```

## Call Indicators

Functions now show correct indicators for their calls:

```elixir
sum_list/1
  ✓ Pure
  Calls:
    λ Enum.reduce/3      # Lambda-dependent indicator

log_and_save/2
  ⚡ Effectful
  Calls:
    ⚡ IO.puts/1          # Effectful indicator
    ⚡ File.write!/2      # Effectful indicator

exception/0
  ⚠ Exception
  Calls:
    ⚠ Kernel.raise/1     # Exception indicator

uppercase/1
  ✓ Pure
  Calls:
    → String.upcase/1    # Pure indicator
```

## Registry Updates

Added missing stdlib functions to `.effects.json`:
- `Process.get/0`, `Process.get/1` → `d` (dependent)
- `Process.put/2`, `Process.delete/1` → `s` (side effects)
- `Process.get_keys/0` → `d` (dependent)
- `List.first/1`, `List.first/2` → `p` (pure)
- `Integer.to_string/1`, `Integer.to_string/2` → `p` (pure)

Changed existing entries:
- `Kernel.apply/2`, `apply/3`: `s` → `u` (unknown)
- `Enum.reduce/3`: `u` → `l` (lambda-dependent)

## Architecture Improvements

### 1. Lambda-Dependent Classification (`ast_walker.ex`)
Added `classify_effect/2` function that:
- Detects function-typed parameters
- Checks if effects are only variables
- Marks as lambda-dependent instead of unknown

### 2. File Discovery (`effect.ex`)
Changed `discover_app_files/0` to:
- Always include `test/support` if it exists
- Not restricted to test environment only

### 3. Pattern Matching Order (`bidirectional.ex`)
Fixed AST pattern order:
- `__block__` before local call pattern
- `__aliases__` for compile-time constructs
- Variables handle any atom context

### 4. Runtime Cache Support (`registry.ex`)
Enhanced cache handling:
- Handles both JSON and compact effect formats
- Returns cached effects directly when atoms/tuples
- Supports cross-module analysis

## Known Limitations

### Standalone File Analysis
When analyzing files not part of a compiled project:
- Local function calls may resolve to `Kernel` module
- Nested modules may not be in cache
- Some cross-module effects may show as unknown

### Workaround
These limitations don't affect real projects where all modules are compiled and cached together.

## Conclusion

The test suite comprehensively covers:
- ✅ All major effect categories (p, l, d, u, e, s)
- ✅ Lambda effect propagation
- ✅ Higher-order function classification
- ✅ Block expression handling
- ✅ Exception detection
- ✅ Cross-module analysis
- ✅ All discovered edge cases
- ✅ All regression bugs

All tests demonstrate correct effect inference behavior and serve as documentation for the expected behavior of the Litmus effect system.
