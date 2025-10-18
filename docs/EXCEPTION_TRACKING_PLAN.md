# Exception Tracking Implementation Plan

## Overview
Add granular exception tracking to Litmus to identify which specific exception types (error/throw/exit) and exception modules can be raised by each function.

## Elixir/Erlang Exception Model

### Three Exception Classes
1. **`:error`** - Exceptions raised with `raise` / `erlang:error/1,2`
   - Examples: `ArgumentError`, `KeyError`, `RuntimeError`
   - Represent actual bugs/exceptional conditions

2. **`:throw`** - Control flow mechanism via `throw/1`
   - Not errors, used for early returns from nested calls
   - Examples: values thrown in comprehensions, early exits

3. **`:exit`** - Process termination via `exit/1`
   - Signal that a process should stop
   - Examples: normal exits, killed processes

All three are caught with `try/catch`:
```elixir
try do
  code()
catch
  :error, exception -> # catches raises
  :throw, value -> # catches throws
  :exit, reason -> # catches exits
end
```

## Data Structures

### 1. Exception Information Type
```elixir
@type exception_class :: :error | :throw | :exit
@type exception_info :: %{
  errors: MapSet.t(module()),      # Exception modules (ArgumentError, etc.)
  throws: :any | :none,             # Throws are untyped
  exits: :any | :none               # Exits are untyped
}
@type exception_result :: %{mfa() => exception_info()}
```

### 2. Extended Purity Result
```elixir
# Current format:
@type purity_result :: %{mfa() => purity_level()}

# New format (backwards compatible):
@type purity_result_with_exceptions :: %{
  mfa() => {purity_level(), exception_info()},
  :_meta => %{has_exceptions: true}
}
```

## Implementation Steps

### Phase 1: Core Infrastructure

#### 1.1 Add Exception Data Types to Litmus (lib/litmus.ex)
```elixir
@type exception_class :: :error | :throw | :exit
@type exception_info :: %{
  errors: MapSet.t(module()),
  throws: :any | :none,
  exits: :any | :none
}
@type exception_result :: %{mfa() => exception_info()}
```

#### 1.2 Create Exception Analysis Module (lib/litmus/exceptions.ex)
New module responsible for:
- Extracting exception information from BEAM bytecode
- Propagating exceptions through call graph
- Merging exception sets
- Querying exception information

Key functions:
```elixir
def extract_exceptions(core_ast) :: exception_info()
def propagate_exceptions(call_graph, initial_exceptions) :: exception_result()
def merge_exceptions(info1, info2) :: exception_info()
def can_raise?(result, mfa, exception_module) :: boolean()
def exceptions_for(result, mfa) :: exception_info()
```

### Phase 2: Exception Extraction

#### 2.1 Detect Exception Raises in BEAM
Scan Core Erlang AST for:
- `erlang:error/1` and `erlang:error/2` calls → extract exception module
- `erlang:throw/1` calls → mark as `:throws = :any`
- `erlang:exit/1` calls → mark as `:exits = :any`
- `{primop, {match_fail, _}}` → `MatchError`
- `{primop, {raise, 2}}` → generic re-raise

Example detection:
```erlang
% In purity_collect.erl style:
handle_exception_call({erlang, error, 1}, [Arg]) ->
  case extract_exception_module(Arg) of
    {ok, Module} -> {error_class, Module}
    :unknown -> {error_class, :unknown}
  end;

handle_exception_call({erlang, error, 2}, [ExceptionArg, _Stacktrace]) ->
  case extract_exception_module(ExceptionArg) of
    {ok, Module} -> {error_class, Module}
    :unknown -> {error_class, :unknown}
  end;

handle_exception_call({erlang, throw, 1}, _Args) ->
  {throw_class, :any};

handle_exception_call({erlang, exit, 1}, _Args) ->
  {exit_class, :any}.

% Helper to extract exception module from AST
extract_exception_module(Arg) ->
  case cerl:type(Arg) of
    call ->
      % Pattern: ExceptionModule.exception(attrs)
      case call_mfa(Arg) of
        {Module, :exception, 1} -> {ok, Module}
        {Module, :exception, 2} -> {ok, Module}
        _ -> :unknown
      end;
    _ ->
      :unknown
  end.
```

#### 2.2 Handle Exception Module Patterns
Common patterns to detect:
```elixir
# Direct raise
raise ArgumentError, "bad arg"
# → erlang:error(ArgumentError.exception("bad arg"))

# Struct creation
raise %ArgumentError{message: "bad arg"}
# → erlang:error(%{__struct__: ArgumentError, ...})

# Re-raise
raise exception
# → erlang:error(exception) where exception is a variable
```

### Phase 3: Exception Propagation

#### 3.1 Propagate Through Call Graph
Algorithm:
1. Start with functions that directly raise exceptions
2. For each function call:
   - Merge caller's exceptions with callee's exceptions
   - Continue until fixpoint (no new exceptions discovered)
3. Handle try/catch blocks:
   - Catch blocks REMOVE exceptions from propagation
   - Only uncaught exceptions propagate to callers

```elixir
def propagate_exceptions(call_graph, purity_results) do
  # Initialize with direct exception raises
  initial = extract_direct_exceptions(call_graph)

  # Propagate through call graph
  fixpoint(initial, fn exceptions ->
    Enum.reduce(call_graph, exceptions, fn {caller, callees}, acc ->
      callee_exceptions =
        callees
        |> Enum.map(&Map.get(exceptions, &1, empty_exception_info()))
        |> merge_all_exceptions()

      # Merge with caller's direct exceptions
      caller_direct = Map.get(initial, caller, empty_exception_info())
      merged = merge_exceptions(caller_direct, callee_exceptions)

      Map.put(acc, caller, merged)
    end)
  end)
end

def merge_exceptions(info1, info2) do
  %{
    errors: MapSet.union(info1.errors, info2.errors),
    throws: merge_flag(info1.throws, info2.throws),
    exits: merge_flag(info1.exits, info2.exits)
  }
end

defp merge_flag(:any, _), do: :any
defp merge_flag(_, :any), do: :any
defp merge_flag(:none, :none), do: :none
```

#### 3.2 Handle Try/Catch Blocks
Exception handlers STOP propagation:
```elixir
# Mark functions with try/catch
def analyze_try_catch(ast) do
  case ast do
    {:try, body, clauses, _catch_clauses, _after} ->
      body_exceptions = analyze(body)
      caught = extract_caught_patterns(catch_clauses)

      # Remove caught exceptions from propagation
      remaining = subtract_exceptions(body_exceptions, caught)
      remaining
  end
end

def extract_caught_patterns(catch_clauses) do
  Enum.reduce(catch_clauses, empty_exception_info(), fn clause, acc ->
    case clause do
      {:catch, :error, pattern} ->
        # Extract specific exception modules from pattern
        %{acc | errors: MapSet.put(acc.errors, extract_module(pattern))}

      {:catch, :throw, _} ->
        %{acc | throws: :any}

      {:catch, :exit, _} ->
        %{acc | exits: :any}
    end
  end)
end
```

### Phase 4: API Updates

#### 4.1 New Analysis Functions (lib/litmus.ex)
```elixir
@doc """
Analyzes a module for exceptions that can be raised.

Returns a map of MFA → exception_info.
"""
@spec analyze_exceptions(module(), options()) :: {:ok, exception_result()} | {:error, term()}
def analyze_exceptions(module, opts \\ [])

@doc """
Combined analysis: purity + exceptions in one pass.
"""
@spec analyze_with_exceptions(module(), options()) ::
  {:ok, %{mfa() => {purity_level(), exception_info()}}} | {:error, term()}
def analyze_with_exceptions(module, opts \\ [])

@doc """
Checks if a function can raise a specific exception.
"""
@spec can_raise?(exception_result(), mfa(), module()) :: boolean()
def can_raise?(results, mfa, exception_module)

@doc """
Gets all exceptions a function can raise.
"""
@spec get_exceptions(exception_result(), mfa()) :: {:ok, exception_info()} | :error
def get_exceptions(results, mfa)

@doc """
Checks if a function can throw (`:throw` class).
"""
@spec can_throw?(exception_result(), mfa()) :: boolean()
def can_throw?(results, mfa)

@doc """
Checks if a function can exit (`:exit` class).
"""
@spec can_exit?(exception_result(), mfa()) :: boolean()
def can_exit?(results, mfa)
```

#### 4.2 Update Litmus.Pure Macro
```elixir
# Add new option to pure macro
defmacro pure(opts \\ [], do: block) do
  level = Keyword.get(opts, :level, :pure)
  require_termination = Keyword.get(opts, :require_termination, false)
  allowed_exceptions = Keyword.get(opts, :allow_exceptions, []) # NEW

  # ... existing code ...

  # Check for disallowed exceptions
  if allowed_exceptions != :any do
    exception_violations =
      calls
      |> Enum.filter(fn call ->
        raises_disallowed_exception?(call, allowed_exceptions)
      end)

    if exception_violations != [] do
      raise_exception_error(exception_violations, allowed_exceptions, __CALLER__)
    end
  end

  block
end
```

Usage:
```elixir
# Allow only ArgumentError
pure allow_exceptions: [ArgumentError] do
  validate_input!(data)  # Can raise ArgumentError
  process(data)           # Must be pure
end

# Allow no exceptions (default)
pure do
  pure_computation()
end

# Allow any exceptions (same as level: :exceptions)
pure allow_exceptions: :any do
  may_raise_anything()
end
```

### Phase 5: Stdlib Exception Whitelist

#### 5.1 Extend Litmus.Stdlib
Add exception information to the whitelist:
```elixir
# In Litmus.Stdlib

@spec exception_whitelist() :: %{mfa() => exception_info()}
def exception_whitelist do
  %{
    # String functions
    {String, :to_integer, 1} => %{
      errors: MapSet.new([ArgumentError]),
      throws: :none,
      exits: :none
    },

    # List functions
    {List, :first, 1} => %{
      errors: MapSet.new([ArgumentError]),
      throws: :none,
      exits: :none
    },

    # Map functions
    {Map, :fetch!, 2} => %{
      errors: MapSet.new([KeyError]),
      throws: :none,
      exits: :none
    },

    # Enum functions (most are exception-free)
    {Enum, :map, 2} => %{
      errors: MapSet.new([]),
      throws: :none,
      exits: :none
    },

    # Integer parsing
    {Integer, :parse, 1} => %{
      errors: MapSet.new([ArgumentError]),
      throws: :none,
      exits: :none
    }

    # Pattern matching
    # Kernel functions that can raise MatchError added automatically
  }
end

@doc """
Gets exception information for a whitelisted function.
"""
@spec get_exception_info(mfa()) :: exception_info() | nil
def get_exception_info(mfa)
```

### Phase 6: Testing

#### 6.1 Test Cases
```elixir
# test/litmus/exceptions_test.exs

defmodule Litmus.ExceptionsTest do
  use ExUnit.Case

  test "detects ArgumentError from String.to_integer/1" do
    {:ok, results} = Litmus.analyze_exceptions(String)
    assert Litmus.can_raise?(results, {String, :to_integer, 1}, ArgumentError)
    refute Litmus.can_raise?(results, {String, :to_integer, 1}, KeyError)
  end

  test "detects throw in custom function" do
    defmodule ThrowExample do
      def thrower(x), do: if x > 10, do: throw(:too_big), else: x
    end

    {:ok, results} = Litmus.analyze_exceptions(ThrowExample)
    assert Litmus.can_throw?(results, {ThrowExample, :thrower, 1})
  end

  test "propagates exceptions through call chain" do
    defmodule PropagateExample do
      def level1(x), do: level2(x)
      def level2(x), do: level3(x)
      def level3(x), do: String.to_integer(x)
    end

    {:ok, results} = Litmus.analyze_exceptions(PropagateExample)
    assert Litmus.can_raise?(results, {PropagateExample, :level1, 1}, ArgumentError)
    assert Litmus.can_raise?(results, {PropagateExample, :level2, 1}, ArgumentError)
    assert Litmus.can_raise?(results, {PropagateExample, :level3, 1}, ArgumentError)
  end

  test "try/catch stops exception propagation" do
    defmodule CatchExample do
      def safe(x) do
        try do
          String.to_integer(x)
        catch
          :error, %ArgumentError{} -> 0
        end
      end
    end

    {:ok, results} = Litmus.analyze_exceptions(CatchExample)
    refute Litmus.can_raise?(results, {CatchExample, :safe, 1}, ArgumentError)
  end

  test "pure macro catches disallowed exceptions" do
    assert_raise Litmus.Pure.ImpurityError, fn ->
      defmodule BadExample do
        import Litmus.Pure

        def example(x) do
          pure do
            String.to_integer(x)  # Raises ArgumentError!
          end
        end
      end
    end
  end

  test "pure macro allows whitelisted exceptions" do
    defmodule GoodExample do
      import Litmus.Pure

      def example(x) do
        pure allow_exceptions: [ArgumentError] do
          String.to_integer(x)  # OK, ArgumentError is allowed
        end
      end
    end
  end
end
```

#### 6.2 NIF Test Cases
```elixir
test "tracks exceptions through NIFs if available" do
  # Create test module with NIF
  defmodule NifExample do
    def nif_function, do: :erlang.nif_error(:not_loaded)
  end

  {:ok, results} = Litmus.analyze_exceptions(NifExample)

  # NIFs should be marked as unknown for exception tracking
  assert Map.get(results, {NifExample, :nif_function, 0}) == :unknown
end
```

### Phase 7: Documentation

#### 7.1 Update README
- Add section on exception tracking
- Show examples of `can_raise?/3`
- Document `allow_exceptions` option in `pure` macro

#### 7.2 Update Module Docs
- Add @doc to all new functions
- Add examples showing exception tracking
- Explain exception propagation algorithm

#### 7.3 Create Guide
Create `guides/exception_tracking.md`:
- How exception tracking works
- Elixir's three exception classes
- How to use exception information
- Limitations and edge cases

## Implementation Checklist

- [ ] Phase 1: Core Infrastructure
  - [ ] Add exception types to Litmus
  - [ ] Create Litmus.Exceptions module

- [ ] Phase 2: Exception Extraction
  - [ ] Detect erlang:error/1,2
  - [ ] Detect erlang:throw/1
  - [ ] Detect erlang:exit/1
  - [ ] Extract exception modules from raise calls
  - [ ] Handle primops (match_fail, raise)

- [ ] Phase 3: Exception Propagation
  - [ ] Implement propagation algorithm
  - [ ] Handle try/catch blocks
  - [ ] Implement fixpoint iteration

- [ ] Phase 4: API Updates
  - [ ] Add analyze_exceptions/2
  - [ ] Add analyze_with_exceptions/2
  - [ ] Add can_raise?/3
  - [ ] Add get_exceptions/2
  - [ ] Add can_throw?/2
  - [ ] Add can_exit?/2
  - [ ] Update pure macro with allow_exceptions

- [ ] Phase 5: Stdlib Whitelist
  - [ ] Add exception_whitelist/0
  - [ ] Document common exception patterns
  - [ ] Add get_exception_info/1

- [ ] Phase 6: Testing
  - [ ] Test direct exception detection
  - [ ] Test exception propagation
  - [ ] Test try/catch handling
  - [ ] Test pure macro integration
  - [ ] Test NIF handling

- [ ] Phase 7: Documentation
  - [ ] Update README
  - [ ] Update module docs
  - [ ] Create exception tracking guide

## Timeline Estimate
- Phase 1: 1 day
- Phase 2: 2-3 days (complex BEAM analysis)
- Phase 3: 2 days
- Phase 4: 1 day
- Phase 5: 1 day
- Phase 6: 2 days
- Phase 7: 1 day

**Total: ~10-11 days of focused development**

## Edge Cases & Limitations

1. **Dynamic exception creation**: If exceptions are created dynamically, we may not be able to determine the exact module
2. **Variable exceptions**: `raise variable` where variable's type is unknown
3. **NIFs**: Native functions can raise any exception, must be marked as unknown
4. **Macros**: Exception raises in macros need special handling
5. **Anonymous functions**: Need to track exceptions from closures
6. **Higher-order functions**: Exception tracking through function arguments

## Future Enhancements

1. **Exception flow analysis**: Track which exceptions propagate through which code paths
2. **Exception documentation**: Generate documentation showing all possible exceptions
3. **IDE integration**: Show exception information in tooltips/autocomplete
4. **Exception coverage**: Track which exceptions are tested
5. **Gradual typing integration**: Use exception information for type checking
