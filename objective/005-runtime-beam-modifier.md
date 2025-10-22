# Objective 005: Runtime BEAM Modifier

## Objective
Implement a system to modify BEAM bytecode at runtime to inject purity checks into dependency modules, ensuring that effects cannot escape from pure blocks even through third-party code.

## Description
Currently, pure blocks can only enforce purity for code compiled with Litmus. Dependencies and stdlib modules bypass these checks. The BEAM modifier will inject effect checking at runtime by modifying module bytecode, creating wrappers, or using other runtime enforcement techniques to guarantee complete purity enforcement.

### Key Problems Solved
- Dependency functions can perform effects in pure blocks
- No runtime enforcement for third-party code
- Effects slip through dependency boundaries
- Cannot enforce purity contracts on external code

## Testing Criteria
1. **Modification Safety**
   - No crashes when modifying modules
   - Concurrent access handled correctly
   - Rollback capability on failure
   - Performance overhead <5% per call

2. **Coverage**
   - User modules: 100% modifiable
   - Elixir stdlib: Best-effort modification
   - Erlang stdlib: Whitelist-based handling
   - NIFs/BIFs: Graceful fallback

3. **Runtime Behavior**
   - Effect checks trigger correctly
   - Proper error messages on violations
   - No interference with normal execution
   - Hot code reload compatibility

## Detailed Implementation Guidance

### WARNING: Technical Spike Required
Before implementing, run spike to verify feasibility:
```elixir
# Test modification safety
defmodule BeamModificationSpike do
  def test_modify_stdlib_module do
    {String, beam_binary, _} = :code.get_object_code(String)
    {:ok, {_, chunks}} = :beam_lib.chunks(beam_binary, [:abstract_code])
    # Attempt modification - likely to fail for NIFs
  end

  def test_concurrent_modification do
    # Spawn 100 processes calling the function
    # Modify module mid-execution
    # Check for crashes/deadlocks
  end
end
```

### File: `lib/litmus/runtime/beam_modifier.ex`

```elixir
defmodule Litmus.Runtime.BeamModifier do
  @moduledoc """
  Modifies BEAM bytecode to inject effect checking at runtime.
  IMPORTANT: This is extremely dangerous and may not be feasible.
  """

  def inject_purity_checks(module) when is_atom(module) do
    case prepare_module_for_modification(module) do
      {:ok, prepared} -> modify_module(prepared)
      {:error, :nif_module} -> {:skip, "NIFs cannot be modified"}
      {:error, :bif_module} -> {:skip, "BIFs cannot be modified"}
      {:error, :no_abstract_code} -> fallback_modification(module)
    end
  end
end
```

### Three Modification Approaches

1. **AST-Level Modification** (Safest)
   ```elixir
   defp modify_via_ast(module, forms) do
     # Transform each function to add checks
     new_forms = Enum.map(forms, &transform_form(&1, module))

     # Recompile module
     case :compile.forms(new_forms) do
       {:ok, ^module, binary, _} ->
         load_modified_module(module, binary)
       {:error, _} ->
         {:error, :compilation_failed}
     end
   end
   ```

2. **Runtime Wrapper** (Fallback)
   ```elixir
   defp modify_via_wrapper(module) do
     # Rename original module
     original_name = :"#{module}_litmus_original"
     rename_module(module, original_name)

     # Create wrapper that delegates through checks
     create_wrapper_module(module, original_name)
   end
   ```

3. **Effect Registry Only** (Last Resort)
   ```elixir
   defp fallback_modification(module) do
     # For unmodifiable modules, register known effects
     case module do
       mod when mod in [:file, :io, :ets] ->
         register_known_effects(mod)
       _ ->
         mark_module_unsafe(module)
     end
   end
   ```

### Critical Considerations

1. **When to Modify**
   - Application startup (one-time cost)
   - On-demand during first pure block (lazy)
   - During dependency compilation (Mix hook)

2. **Concurrency Safety**
   ```elixir
   def safe_modify(module) do
     # Create modified version with new name first
     temp_module = :"#{module}_temp"
     create_modified(module, temp_module)

     # Atomic swap
     :global.trans(
       {{:litmus_modify, module}, self()},
       fn ->
         :code.purge(module)
         rename_module(temp_module, module)
       end
     )
   end
   ```

3. **Rollback Strategy**
   - Keep original BEAM files
   - Provide `mix litmus.rollback` command
   - Auto-rollback on startup failures

## State of Project After Implementation

### Improvements
- **Effect enforcement**: 100% coverage including dependencies
- **Runtime safety**: No effects escape pure blocks
- **Third-party code**: Subject to purity constraints
- **Contract validation**: Dependencies meet purity expectations

### New Capabilities
- Runtime purity enforcement for all code
- Effect violation detection in production
- Dependency purity contracts
- Module modification audit log
- Performance profiling of effect checks

### Files Modified
- Created: `lib/litmus/runtime/beam_modifier.ex`
- Created: `lib/litmus/runtime/effect_guard.ex`
- Created: `lib/mix/tasks/litmus.rollback.ex`
- Modified: `lib/litmus/pure.ex` (integrate modifier)

### Limitations
- Cannot modify NIFs (native code)
- Cannot modify BIFs (built-in functions)
- Hot code reload may restore originals
- Performance impact on modified modules

### Risk Mitigation
- Feature flag for opt-in/out
- Extensive testing before enabling
- Graceful degradation on failure
- Clear documentation of limitations

## Next Recommended Objective

**Objective 006: Module Cache Strategy**

After implementing runtime modification, create a sophisticated caching system that tracks module versions, effect classifications, and modification status. This will minimize the performance impact of runtime checks and enable instant analysis updates during development.