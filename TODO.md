# Litmus Effect System - TODO List

This document tracks planned improvements and known limitations of the Litmus effect inference system.

## High Priority

### 1. Pattern Matching in Lambdas
**Status**: Not implemented
**Priority**: High
**Impact**: Functions with pattern-matching lambdas are incorrectly marked as unknown

**Problem**:
Lambda parameters with pattern matching (e.g., `fn {k, v} -> ...`, `fn [h | t] -> ...`) currently produce unknown effects instead of properly inferring the lambda body's effects.

**Affected Functions**:
- `complex_pipeline/1` in `test/infer/infer_test.exs:207`
- `lambda_with_pattern_match/1` in `test/infer/infer_test.exs:240`

**Example**:
```elixir
# Currently shows as unknown, should be pure
def process_tuples(list) do
  Enum.map(list, fn {k, v} -> {k, v * 2} end)
end
```

**Solution Approach**:
1. Enhance `handle_lambda` in `bidirectional.ex` to handle pattern matching in parameters
2. Extract pattern bindings and add them to the lambda's context
3. Support common patterns: tuples, lists, maps, structs
4. Infer effects from the lambda body with pattern-bound variables

**Files to Modify**:
- `lib/litmus/inference/bidirectional.ex` - Update `handle_lambda/4` and `infer_type/4`
- `lib/litmus/inference/context.ex` - May need pattern binding support

---

### 2. Specific Exception Type Tracking
**Status**: Partial implementation
**Priority**: High
**Impact**: All exceptions are treated uniformly; cannot distinguish between different exception types

**Problem**:
The current system tracks that a function can raise exceptions (`:exn` label), but doesn't distinguish between different exception types like `ArgumentError`, `ArithmeticError`, `KeyError`, etc.

**Current Behavior**:
```elixir
def divide(a, b), do: div(a, b)  # Shows as {:e, [:exn]}
def validate!(x), do: raise ArgumentError  # Shows as {:e, [:exn]}
```

**Desired Behavior**:
```elixir
def divide(a, b), do: div(a, b)  # Should show {:e, [:arithmetic]}
def validate!(x), do: raise ArgumentError  # Should show {:e, [:argument]}
def lookup!(map, key), do: Map.fetch!(map, key)  # Should show {:e, [:key]}
```

**Benefits**:
- More precise effect tracking
- Better error documentation
- Enable exception-specific handling in calling code
- Support for "catches" analysis (which exceptions are handled)

**Solution Approach**:
1. Extend effect row type system to track specific exception types
2. Update `.effects.json` to include exception types for stdlib functions:
   ```json
   {
     "Kernel": {
       "div/2": {"e": ["arithmetic"]},
       "hd/1": {"e": ["argument"]},
       "raise/2": "u"  // Unknown - depends on first argument
     },
     "Map": {
       "fetch!/2": {"e": ["key"]}
     }
   }
   ```
3. Infer exception types from `raise` expressions by analyzing the exception module
4. Combine exception types when multiple exceptions possible
5. Update display to show specific exception types

**Files to Modify**:
- `.effects.json` - Add exception type annotations
- `lib/litmus/types/effects.ex` - Support `:exn` labels with subtypes
- `lib/litmus/types/core.ex` - Update `to_compact_effect` for exception types
- `lib/litmus/inference/bidirectional.ex` - Infer specific exception types from `raise`
- `lib/mix/tasks/effect.ex` - Display specific exception types

**Exception Type Taxonomy**:
```
:exn (root exception effect)
├── :argument      - ArgumentError, FunctionClauseError
├── :arithmetic    - ArithmeticError (div by zero, etc)
├── :key           - KeyError
├── :match         - MatchError
├── :case          - CaseClauseError
├── :cond          - CondClauseError
├── :badmap        - BadMapError
├── :badbool       - BadBooleanError
├── :badstruct     - BadStructError
├── :enum          - Enum.EmptyError, Enum.OutOfBoundsError
├── :protocol      - Protocol.UndefinedError
├── :undef         - UndefinedFunctionError
├── :compile       - CompileError, SyntaxError, TokenMissingError
├── :runtime       - RuntimeError
├── :system        - SystemLimitError
└── :unknown       - Other/unknown exception types
```

---

### 3. Specific Effect Label Tracking
**Status**: Partial implementation
**Priority**: Medium
**Impact**: All side effects are treated uniformly; cannot distinguish between I/O, process operations, ETS, etc.

**Problem**:
The current system marks functions with side effects as `:s`, but doesn't distinguish between different types of effects like `:io`, `:file`, `:process`, `:ets`, `:network`, etc.

**Current Behavior**:
```elixir
def log(msg), do: IO.puts(msg)          # Shows as :s
def save(path, data), do: File.write!(path, data)  # Shows as :s
def spawn_task(f), do: spawn(f)        # Shows as :s
```

**Desired Behavior**:
```elixir
def log(msg), do: IO.puts(msg)          # Should show {:s, [:io]}
def save(path, data), do: File.write!(path, data)  # Should show {:s, [:file]}
def spawn_task(f), do: spawn(f)        # Should show {:s, [:process]}
def save_and_log(path, msg) do          # Should show {:s, [:io, :file]}
  IO.puts(msg)
  File.write!(path, msg)
end
```

**Benefits**:
- More precise effect tracking
- Enable effect-specific analysis (e.g., "which functions perform I/O?")
- Better documentation of what side effects a function performs
- Support for capability-based security models

**Effect Label Taxonomy**:
```
:s (root side effect)
├── :io           - Console I/O (IO.puts, IO.inspect, etc)
├── :file         - File system operations (File.read!, File.write!, etc)
├── :process      - Process operations (spawn, send, receive, Process.*)
├── :ets          - ETS table operations
├── :dets         - DETS table operations
├── :network      - Network operations (:gen_tcp, :gen_udp, :ssl, etc)
├── :random       - Random number generation (:rand, :random)
├── :time         - Time/date operations (DateTime.utc_now, System.system_time)
├── :env          - Environment variables (System.get_env, System.put_env)
├── :code         - Code loading/compilation (Code.eval_string, Code.compile_file)
├── :application  - OTP Application operations (Application.put_env, etc)
└── :unknown      - Other/unknown side effects
```

**Solution Approach**:
1. Extend effect row type system to track specific effect labels
2. Update `.effects.json` to include effect labels:
   ```json
   {
     "Elixir.IO": {
       "puts/1": {"s": ["io"]},
       "inspect/2": {"s": ["io"]}
     },
     "Elixir.File": {
       "read!/1": {"s": ["file"]},
       "write!/2": {"s": ["file"]}
     },
     "Elixir.Process": {
       "spawn/1": {"s": ["process"]},
       "send/2": {"s": ["process"]}
     }
   }
   ```
3. Combine effect labels when multiple effects present
4. Update display to show specific effect types

**Files to Modify**:
- `.effects.json` - Add effect label annotations
- `lib/litmus/types/effects.ex` - Support `:s` labels with subtypes
- `lib/litmus/types/core.ex` - Update `to_compact_effect` for effect labels
- `lib/mix/tasks/effect.ex` - Display specific effect types

---

## Medium Priority

### 4. Function Capture Effect Inference Improvement
**Status**: Partial implementation
**Priority**: Medium
**Impact**: Function captures often produce lambda-dependent effects even when they could be pure

**Problem**:
Function captures like `&String.upcase/1` currently create lambda-dependent effects, even though we know `String.upcase/1` is pure and the capture should also be pure.

**Current Behavior**:
```elixir
def process_strings(list) do
  Enum.map(list, &String.upcase/1)  # Shows as lambda-dependent
end
```

**Desired Behavior**:
```elixir
def process_strings(list) do
  Enum.map(list, &String.upcase/1)  # Should show as pure
end
```

**Solution Approach**:
1. In `handle_capture` in `bidirectional.ex`, look up the captured function's effect
2. If the captured function has a known effect (from registry or cache), use that effect
3. Only mark as lambda-dependent if the captured function's effect is unknown

**Files to Modify**:
- `lib/litmus/inference/bidirectional.ex` - Update `handle_capture/4`

---

### 5. Local Function Call Resolution
**Status**: Not implemented
**Priority**: Medium
**Impact**: Functions calling local functions show as unknown when analyzed standalone

**Problem**:
When analyzing a module standalone (not part of a full compilation), local function calls are not resolved and show as unknown.

**Current Behavior**:
```elixir
defmodule MyModule do
  def public_func(x) do
    private_helper(x)  # Shows as unknown when analyzed standalone
  end

  defp private_helper(x), do: x * 2
end
```

**Solution Approach**:
1. During `ASTWalker.analyze_ast/1`, build a map of all functions in the module first
2. Store this in the context or a separate cache
3. When analyzing a function, check if called functions are in the same module
4. If yes, use the analyzed effect from the module's function map
5. Support mutual recursion by using effect variables and unification

**Files to Modify**:
- `lib/litmus/analyzer/ast_walker.ex` - Build module function map before analysis
- `lib/litmus/inference/bidirectional.ex` - Check module function map for local calls

---

### 6. Registry Completeness Validation
**Status**: Partial implementation
**Priority**: Medium
**Impact**: Missing stdlib functions cause runtime errors

**Problem**:
The registry raises `MissingStdlibEffectError` for stdlib functions not in `.effects.json`, but there's no systematic way to find missing functions.

**Desired Features**:
1. Mix task to scan all stdlib modules and compare with registry
2. Report missing functions with their module/function/arity
3. Suggest effect classifications based on similar functions
4. Option to auto-generate registry entries with conservative defaults

**Implementation**:
Create `mix effect.registry.validate` task that:
1. Loads all stdlib modules (Elixir.* and erlang modules)
2. Extracts all exported functions
3. Compares with `.effects.json` entries
4. Reports missing functions grouped by module
5. Suggests likely effect types based on function name patterns

**Files to Create**:
- `lib/mix/tasks/effect/registry/validate.ex`

---

## Low Priority

### 7. Effect Polymorphism for Generic Functions
**Status**: Not implemented
**Priority**: Low
**Impact**: Some polymorphic functions are overly conservative

**Problem**:
Functions like `Enum.map/2` are lambda-dependent, but when we know the lambda is pure at compile time, we should be able to infer that the whole call is pure.

**Current Behavior**:
```elixir
defmodule MyModule do
  def double_list(list) do
    Enum.map(list, fn x -> x * 2 end)  # Pure lambda, but Enum.map is 'l'
  end
end
```

**Desired Behavior**:
Should detect that the lambda is pure and resolve `Enum.map` call to pure instead of lambda-dependent.

**Solution Approach**:
This requires more sophisticated effect polymorphism:
1. Represent lambda-dependent functions with effect variables: `Enum.map :: (list(a), (a -> b | e)) -> list(b) | e`
2. When analyzing a call to `Enum.map` with a known-pure lambda, substitute the effect variable
3. This requires full row-polymorphic effect inference

**Files to Modify**:
- Major refactoring of the type and effect system
- This is a larger research project

---

### 8. Dependency Effect Analysis
**Status**: Not implemented
**Priority**: Low
**Impact**: Third-party library functions show as unknown

**Problem**:
Functions from dependencies (hex packages) have unknown effects unless manually added to `.effects.json`.

**Desired Features**:
1. Analyze dependency source code and cache effects in `.effects/deps`
2. Mix task to generate effect files for dependencies: `mix effect.deps.generate`
3. Support for publishing effect annotations with hex packages (metadata)
4. Community registry of common library effects

**Implementation**:
1. During compilation, analyze dependency beam files or source
2. Cache results in `.effects/deps/<package_name>`
3. Load these during effect lookups

**Files to Create**:
- `lib/mix/tasks/effect/deps/generate.ex`

---

### 9. Interactive Effect Refinement
**Status**: Not implemented
**Priority**: Low
**Impact**: Quality of life improvement for developers

**Problem**:
When effects are unknown or incorrectly inferred, there's no easy way to provide hints or override the inference.

**Desired Features**:
1. Allow developers to add effect annotations in code:
   ```elixir
   @effect :p  # Mark as pure
   def my_complex_function(x) do
     # Complex logic that the inference can't figure out
   end
   ```
2. Validate annotations against inferred effects
3. Warn if annotation conflicts with inference
4. Use annotations as ground truth for refinement

**Files to Modify**:
- `lib/litmus/analyzer/ast_walker.ex` - Extract `@effect` attributes
- `lib/litmus/inference/bidirectional.ex` - Use annotations during inference

---

## Documentation & Tooling

### 10. Comprehensive Documentation
**Status**: Partial
**Priority**: Medium

**Tasks**:
- [ ] Document effect system architecture and design decisions
- [ ] Add examples for each effect type
- [ ] Create tutorial for adding new stdlib functions to registry
- [ ] Document limitations and known issues
- [ ] Add contributing guide for effect system improvements

---

### 11. Better Error Messages
**Status**: Basic implementation
**Priority**: Medium

**Improvements Needed**:
- [ ] Show source location for unknown effects
- [ ] Suggest possible fixes (e.g., "add to .effects.json")
- [ ] Pretty-print effect types in error messages
- [ ] Add context about why an effect was inferred

---

### 12. Performance Optimization
**Status**: Not implemented
**Priority**: Low

**Known Issues**:
- [ ] Large codebases may be slow to analyze
- [ ] Effect unification can be expensive
- [ ] Runtime cache is not persistent across runs

**Potential Optimizations**:
- [ ] Incremental analysis (only re-analyze changed modules)
- [ ] Parallel analysis of independent modules
- [ ] Persistent effect cache (SQLite or similar)
- [ ] Memoization of commonly analyzed patterns

---

## Research & Experimentation

### 13. Effect Handlers and Algebraic Effects
**Status**: Experimental
**Priority**: Research

**Exploration Areas**:
- [ ] Effect handlers for runtime effect management
- [ ] Integration with CPS transformation for effect handling
- [ ] Algebraic effect operations (perform, handle)
- [ ] Effect resumption and continuation support

---

### 14. Effect-Based Optimization
**Status**: Not implemented
**Priority**: Research

**Ideas**:
- [ ] Use purity information for compiler optimizations
- [ ] Dead code elimination based on unused effects
- [ ] Automatic parallelization of pure computations
- [ ] Memoization of pure functions

---

## Notes

### Known Limitations
1. **Pattern matching in lambdas** - Produces unknown effects
2. **Local function calls** - Show as unknown when analyzed standalone
3. **Dynamic function calls** - `apply/3`, `Kernel.apply/2` always unknown
4. **Metaprogramming** - `Code.eval_string/1`, macros not tracked
5. **Erlang functions** - Limited coverage in registry

### Testing Status
- ✅ 92/92 tests passing
- ✅ Edge cases documented and tested
- ✅ Regression tests for all bug fixes
- ✅ Comprehensive inference tests

### Recent Improvements (October 2025)
- ✅ Fixed lambda-dependent function classification
- ✅ Fixed block expression effect combination
- ✅ Fixed variable recognition with module context
- ✅ Fixed exception effect detection
- ✅ Fixed cross-module effect cache handling
- ✅ Created `mix effect.cache.clean` task
- ✅ Added comprehensive test suites
- ✅ Documented all bugs and fixes in regression tests

---

*This TODO list is a living document. Please update it as features are implemented or new issues are discovered.*
