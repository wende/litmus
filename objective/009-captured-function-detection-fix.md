# Objective 009: Captured Function Detection Fix

## Objective
Fix the critical bug where captured functions (&Module.function/arity) are explicitly skipped during purity analysis, allowing effectful functions to slip through pure blocks undetected.

## Description
There's a bug in `lib/litmus/pure.ex` lines 485-494 where captured functions return `nil` and are skipped during effect checking. This allows expressions like `Enum.each(list, &IO.puts/1)` to execute in pure blocks without any compilation error. This is one of the 7 major paths for effect leakage and must be fixed immediately.

### Key Problems Solved
- Captured functions bypass purity checks
- Effects slip through via &Module.function/arity syntax
- Higher-order functions with captured effects not detected
- No warning or error for effectful captures

## Testing Criteria
1. **Detection Coverage**
   - All captured functions properly analyzed
   - Both &Module.function/arity and &function/arity forms handled
   - Captured lambdas checked for effects
   - Remote and local captures distinguished

2. **Error Reporting**
   - Clear compilation errors for effectful captures
   - Proper error messages with location info
   - Suggestions for fixing the issue
   - No false positives for pure captures

3. **Integration**
   - Works with Enum functions
   - Works with Stream functions
   - Works with Task/Agent spawning
   - No performance regression

## Detailed Implementation Guidance

### Current Bug Location: `lib/litmus/pure.ex`

```elixir
# CURRENT BUGGY CODE (lines 485-494):
defp extract_call({{:., _}, _, args}) when is_atom(args) do
  nil  # BUG: Returns nil, causing captures to be skipped!
end

defp extract_call({:&, _, [{:/, _, [{{:., _, [module, function]}, _, _}, arity]}]}) do
  nil  # BUG: Another place where captures are ignored!
end
```

### Fixed Implementation

```elixir
# FIXED CODE:
defp extract_call({:&, _, [{:/, _, [{{:., _, [module, function]}, _, _}, arity]}]})
    when is_atom(module) and is_atom(function) and is_integer(arity) do
  # This is a capture like &IO.puts/1
  {module, function, arity}
end

defp extract_call({:&, _, [{:/, _, [{function, _, _}, arity]}]})
    when is_atom(function) and is_integer(arity) do
  # This is a local capture like &helper/2
  # Need to track current module context
  module = get_current_module()
  {module, function, arity}
end

defp extract_call({{:., meta}, env, args}) when is_list(args) do
  # Handle captured calls with partial application
  case analyze_capture(args, meta, env) do
    {:ok, mfa} -> mfa
    :error -> nil
  end
end

defp analyze_capture(args, meta, env) do
  # Detailed analysis of capture forms
  case args do
    [module, function] when is_atom(module) and is_atom(function) ->
      # Try to determine arity from context
      arity = infer_capture_arity(meta, env)
      {:ok, {module, function, arity}}

    _ ->
      :error
  end
end
```

### Complete Fix Implementation

```elixir
defmodule Litmus.Pure.CaptureFix do
  @moduledoc """
  Fixed capture detection for pure macro.
  """

  def extract_call(ast, context \\ %{}) do
    case ast do
      # Standard function call
      {{:., _, [module, function]}, _, args}
          when is_atom(module) and is_atom(function) and is_list(args) ->
        {module, function, length(args)}

      # Capture with explicit arity: &Module.function/arity
      {:&, _, [{:/, _, [{{:., _, [module, function]}, _, _}, arity]}]}
          when is_atom(module) and is_atom(function) and is_integer(arity) ->
        {module, function, arity}

      # Local capture: &function/arity
      {:&, _, [{:/, _, [{function, _, nil}, arity]}]}
          when is_atom(function) and is_integer(arity) ->
        module = Map.get(context, :current_module, nil)
        if module do
          {module, function, arity}
        else
          nil
        end

      # Capture without explicit arity: &Module.function
      {:&, _, [{{:., _, [module, function]}, _, []}]}
          when is_atom(module) and is_atom(function) ->
        # Need to infer arity from usage context
        arity = infer_arity_from_context(ast, context)
        {module, function, arity}

      # Anonymous function capture: &(&1 + &2)
      {:&, _, [body]} ->
        analyze_anonymous_capture(body, context)

      _ ->
        nil
    end
  end

  defp infer_arity_from_context(ast, context) do
    # Look at parent AST node to determine expected arity
    case Map.get(context, :parent_call) do
      {Enum, :map, _} -> 1  # Enum.map expects arity 1
      {Enum, :reduce, _} -> 2  # Enum.reduce expects arity 2
      {Enum, :filter, _} -> 1  # Enum.filter expects arity 1
      _ -> :unknown
    end
  end

  defp analyze_anonymous_capture(body, context) do
    # Count &1, &2, etc. to determine arity
    max_arg = find_max_capture_arg(body)

    # Extract any function calls within the capture
    calls = extract_calls_from_body(body, context)

    # Return the most restrictive effect
    merge_effects(calls)
  end

  defp find_max_capture_arg(ast) do
    {_, max} = Macro.postwalk(ast, 0, fn
      {:&, _, [n]}, acc when is_integer(n) ->
        {:&, [], [n]}, max(n, acc)
      node, acc ->
        node, acc
    end)
    max
  end
end
```

### Integration with Pure Macro

```elixir
defmodule Litmus.Pure do
  # ... existing code ...

  defp check_purity(ast, context) do
    # Walk the AST and check all function calls
    Macro.postwalk(ast, fn node ->
      case CaptureFix.extract_call(node, context) do
        {module, function, arity} = mfa ->
          # Check if this MFA is pure
          unless pure?(mfa) do
            raise Litmus.ImpurityError,
              mfa: mfa,
              location: extract_location(node),
              context: "Captured function is not pure"
          end

        nil ->
          :ok
      end

      node
    end)
  end
end
```

### Test Cases to Add

```elixir
defmodule CaptureDetectionTest do
  use ExUnit.Case
  import Litmus.Pure

  test "detects captured IO functions" do
    assert_raise Litmus.ImpurityError, fn ->
      Code.eval_string("""
      import Litmus.Pure
      pure do
        Enum.each([1, 2, 3], &IO.puts/1)
      end
      """)
    end
  end

  test "allows captured pure functions" do
    result = pure do
      Enum.map([1, 2, 3], &String.to_integer/1)
    end
    assert result == [1, 2, 3]
  end

  test "detects nested captured effects" do
    assert_raise Litmus.ImpurityError, fn ->
      pure do
        [1, 2, 3]
        |> Enum.map(&to_string/1)
        |> Enum.each(&IO.puts/1)  # Should be caught!
      end
    end
  end

  test "detects anonymous captures with effects" do
    assert_raise Litmus.ImpurityError, fn ->
      pure do
        Enum.map([1, 2, 3], &(IO.puts(&1)))
      end
    end
  end
end
```

## State of Project After Implementation

### Improvements
- **Effect leakage paths**: Reduced from 7 to 6
- **Capture detection**: 100% of captures analyzed
- **False negatives**: Major source eliminated
- **User confidence**: Can trust pure blocks more

### New Capabilities
- Full analysis of captured functions
- Arity inference for captures
- Anonymous capture analysis
- Better error messages for capture violations

### Files Modified
- Modified: `lib/litmus/pure.ex` (lines 485-494)
- Created: `lib/litmus/pure/capture_fix.ex`
- Created: `test/pure/capture_detection_test.exs`
- Updated: Documentation about capture handling

### Before/After Examples
```elixir
# BEFORE (Bug allows this):
pure do
  Enum.each([1, 2, 3], &IO.puts/1)  # No error!
end

# AFTER (Fixed - proper error):
pure do
  Enum.each([1, 2, 3], &IO.puts/1)
  # Compilation error: Impure function call detected
  # Function: Elixir.IO.puts/1
  # Effect type: Side effects (I/O)
end
```

## Next Recommended Objective

**Objective 010: Unified Pure Macro Rewrite**

With captured function detection fixed, undertake a complete rewrite of the pure macro to integrate all improvements: pre-analyze dependencies, transform with CPS before verification, verify at AST level, and provide runtime enforcement. This will be the capstone that brings all features together.