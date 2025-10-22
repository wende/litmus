# Objective 004: CPS Transformation Completion

## Objective
Extend the CPS (Continuation-Passing Style) transformer to support all Elixir control flow constructs, enabling the effect macro to work with any code pattern including cond, with, recursive functions, multi-clause functions, try/catch/rescue, and receive blocks.

## Description
The current CPS transformer only handles if/else and case expressions (70% complete). This limits the effect macro's usefulness as it cannot transform common Elixir patterns like with expressions, cond statements, or recursive functions. Completing the transformer enables full algebraic effects support for comprehensive testing and mocking.

### Key Problems Solved
- Effect macro fails on cond, with, recursive functions
- Cannot mock effects in OTP behaviors (receive blocks)
- Incomplete support for exception handling in effects
- No tail-call optimization for recursive effects

## Testing Criteria
1. **Control Flow Coverage**
   - `cond` expressions with effects in conditions and branches
   - `with` expressions with pattern matching and else clauses
   - Recursive functions with tail-call optimization
   - Multi-clause functions with different arities
   - `try/catch/rescue/after` blocks
   - `receive` blocks with timeout

2. **Semantic Preservation**
   - Transformed code produces identical results
   - Pattern matching semantics preserved
   - Guard expressions work correctly
   - Exception propagation unchanged
   - Message ordering in receive blocks maintained

3. **Performance**
   - No stack overflow on deep recursion
   - Minimal closure allocation
   - Tail calls properly optimized
   - Compile-time transformation (no runtime overhead)

## Detailed Implementation Guidance

### File: `lib/litmus/effects/transformer/control_flow.ex`

```elixir
defmodule Litmus.Effects.Transformer.ControlFlow do
  @moduledoc """
  CPS transformation for all Elixir control flow constructs.
  """

  # COND EXPRESSIONS
  defp transform_ast({:cond, meta, [[do: clauses]]}, opts) do
    cont_var = Macro.var(:__litmus_cont, __MODULE__)

    transformed_clauses = Enum.map(clauses, fn {:->, clause_meta, [[condition], body]} ->
      # Transform condition (may have effects!)
      {transformed_condition, condition_effects} = transform_expression(condition, opts)

      # Transform body with continuation
      transformed_body = transform_block(body, opts)

      # Handle effects in condition
      if has_effects?(condition_effects) do
        wrap_with_effect_handler(condition_effects, transformed_body, cont_var)
      else
        {:->, clause_meta, [[transformed_condition],
          quote do: unquote(transformed_body).(unquote(cont_var))]
        }
      end
    end)

    # Build cond with continuation threading
    quote do
      fn unquote(cont_var) ->
        cond do
          unquote_splicing(transformed_clauses)
        end
      end
    end
  end
end
```

### Key Transformations

1. **WITH Expressions**
   ```elixir
   # Pattern matching with early returns
   defp transform_with_steps([], do_block, _else_clauses, opts) do
     transform_block(do_block, opts)
   end

   defp transform_with_steps([{:<-, _, [pattern, expr]} | rest], do_block, else_clauses, opts) do
     {transformed_expr, expr_effects} = transform_expression(expr, opts)
     rest_transformation = transform_with_steps(rest, do_block, else_clauses, opts)

     quote do
       fn __cont ->
         unquote(expr_effects).(fn expr_result ->
           case expr_result do
             unquote(pattern) ->
               unquote(rest_transformation).(__cont)
             other ->
               unquote(transform_else_clauses(else_clauses, opts)).(__cont, other)
           end
         end)
       end
     end
   end
   ```

2. **Recursive Functions**
   ```elixir
   # Add recursion point parameter
   defp transform_recursive_function(name, args, body, opts) do
     rec_param = Macro.var(:__rec, __MODULE__)

     # Create recursion wrapper
     rec_name = :"#{name}_rec"

     # Transform body with recursion context
     rec_opts = Map.put(opts, :recursion_point, {rec_name, length(args)})
     transformed_body = transform_block(body, rec_opts)

     quote do
       def unquote(name)(unquote_splicing(args)) do
         rec_point = fn unquote_splicing(args), cont ->
           unquote(rec_name)(unquote_splicing(args), cont, rec_point)
         end

         unquote(rec_name)(unquote_splicing(args), &(&1), rec_point)
       end

       defp unquote(rec_name)(unquote_splicing(args), cont, rec) do
         unquote(transformed_body)
       end
     end
   end
   ```

3. **Try/Catch/Rescue**
   ```elixir
   # Preserve exception semantics with CPS
   defp transform_try(try_block, rescue_clauses, catch_clauses, after_block, opts) do
     quote do
       fn cont ->
         try do
           # Execute transformed block with error-catching continuation
           error_cont = fn
             {:litmus_effect_error, effect} ->
               raise Litmus.Effects.UnhandledError, effect: effect
             {:litmus_exception, kind, reason, stacktrace} ->
               :erlang.raise(kind, reason, stacktrace)
             result ->
               cont.(result)
           end

           unquote(transform_block(try_block, opts)).(error_cont)
         unquote_splicing(transform_exception_clauses(rescue_clauses, :rescue, cont, opts))
         unquote_splicing(transform_exception_clauses(catch_clauses, :catch, cont, opts))
         after
           unquote(if after_block, do: transform_block(after_block, opts))
         end
       end
     end
   end
   ```

### Critical Implementation Details

1. **Effect Detection in Conditions**
   - Guards may contain effects
   - Must evaluate with effect handling
   - Preserve short-circuit evaluation

2. **Pattern Matching Semantics**
   - Failed patterns trigger else clauses
   - Variables bound in patterns available in continuation
   - Anonymous variables don't create bindings

3. **Tail Call Optimization**
   - Detect tail position accurately
   - Use trampoline if needed
   - Avoid stack growth

4. **Exception Propagation**
   - Maintain proper stacktraces
   - After blocks must execute
   - Effects in rescue clauses

## State of Project After Implementation

### Improvements
- **CPS Coverage**: From 70% to 100% of language constructs
- **Effect macro usability**: Works with any Elixir code
- **Test coverage**: Can mock effects in any context
- **OTP compatibility**: Works with GenServer callbacks

### New Capabilities
- Mock effects in with expressions
- Test recursive algorithms with mocked I/O
- Intercept effects in OTP behaviors
- Full exception handling in effect blocks
- Pattern matching in effect handlers

### Files Modified
- Created: `lib/litmus/effects/transformer/control_flow.ex`
- Modified: `lib/litmus/effects/transformer.ex` (add new cases)
- Created: `test/effects/control_flow_test.exs`
- Updated: `lib/litmus/effects.ex` (documentation)

### Usage Examples
```elixir
# Now works with all constructs
effect do
  with {:ok, data} <- File.read("config.json"),
       {:ok, parsed} <- Jason.decode(data),
       :ok <- validate(parsed) do
    process_data(parsed)
  else
    {:error, reason} -> handle_error(reason)
  end
catch
  {File, :read, _} -> {:ok, ~s({"test": true})}
end
```

## Next Recommended Objective

**Objective 008: Unknown Classification Elimination**

With complete CPS transformation and recursive analysis in place, focus on eliminating the remaining :unknown classifications by implementing conservative inference strategies, improving dynamic dispatch analysis, and adding support for metaprogramming patterns. This will bring unknown classifications from ~5% to near 0%.