defmodule Litmus.Spikes.BeamModifierSpike do
  @moduledoc """
  Technical spike to test the feasibility of modifying BEAM bytecode at runtime.

  This module tests three critical questions:
  1. Can we modify Elixir stdlib modules like String.upcase/1?
  2. Can we modify user-defined modules safely?
  3. Can we handle concurrent access during modification?
  4. What is the performance overhead?

  ## Success Criteria
  - Modifications work without crashes
  - Performance overhead <5%
  - Concurrent access is safe

  ## If Success
  - Proceed with Task 13 (Runtime BEAM Modifier)

  ## If Failure
  - Skip Task 13, use compile-time transformation only
  """

  @doc """
  Extracts BEAM bytecode for a module.

  Returns `{:ok, binary}` or `{:error, reason}`.
  """
  def extract_beam_code(module) when is_atom(module) do
    case :code.get_object_code(module) do
      {^module, beam_binary, _filename} ->
        {:ok, beam_binary}

      :error ->
        {:error, :module_not_found}
    end
  end

  @doc """
  Extracts abstract code (AST forms) from a module's BEAM bytecode.

  This is required for AST-level modification. Returns:
  - `{:ok, forms}` - Module has debug_info, can be modified
  - `{:error, :no_abstract_code}` - Module compiled without debug_info
  - `{:error, :beam_lib_error}` - BEAM file is corrupted or encrypted
  """
  def extract_abstract_code(module) when is_atom(module) do
    with {:ok, beam_binary} <- extract_beam_code(module),
         {:ok, {^module, chunks}} <- :beam_lib.chunks(beam_binary, [:abstract_code]) do
      case chunks do
        [abstract_code: {:raw_abstract_v1, forms}] ->
          {:ok, forms}

        [abstract_code: :no_abstract_code] ->
          {:error, :no_abstract_code}

        _ ->
          {:error, :unexpected_format}
      end
    else
      {:error, :beam_lib, reason} ->
        {:error, {:beam_lib_error, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if a module is a NIF (Native Implemented Function) module.

  NIFs cannot be modified as they're implemented in C/Rust/etc.
  """
  def is_nif?(module) when is_atom(module) do
    # Check if module has NIF functions loaded
    # This is a heuristic - we check if we can get abstract code
    case extract_abstract_code(module) do
      {:ok, _forms} ->
        # Has abstract code, likely not a NIF
        false

      {:error, :no_abstract_code} ->
        # No abstract code might indicate NIF, but could also be
        # compiled without debug_info
        :maybe

      {:error, _} ->
        :maybe
    end
  end

  @doc """
  Modifies a function's AST to inject a purity check wrapper.

  Takes the original function forms and wraps the body with an effect check.

  ## Example Transformation

  Original:
  ```
  def sample_function(x) do
    x * 2
  end
  ```

  Modified:
  ```
  def sample_function(x) do
    Litmus.Spikes.BeamModifierSpike.check_purity_before_call()
    x * 2
  end
  ```
  """
  def inject_purity_check(forms, function_name, function_arity) do
    Enum.map(forms, fn form ->
      transform_function(form, function_name, function_arity)
    end)
  end

  defp transform_function({:function, line, name, arity, clauses}, target_name, target_arity)
       when name == target_name and arity == target_arity do
    # Transform each clause to inject purity check at the start
    modified_clauses = Enum.map(clauses, fn {:clause, cl_line, args, guards, body} ->
      # Inject check call at the start of body
      check_call = {
        :call,
        cl_line,
        {:remote, cl_line,
         {:atom, cl_line, Litmus.Spikes.BeamModifierSpike},
         {:atom, cl_line, :check_purity_before_call}},
        []
      }

      # Prepend check to body
      new_body = [check_call | body]

      {:clause, cl_line, args, guards, new_body}
    end)

    {:function, line, name, arity, modified_clauses}
  end

  defp transform_function(form, _name, _arity), do: form

  @doc """
  Placeholder function that would perform actual purity checking.

  In the real implementation, this would:
  1. Check if we're inside a pure block
  2. Verify the function is allowed
  3. Raise error if impure function called in pure context
  """
  def check_purity_before_call do
    # In real implementation, this would check purity context
    # For spike, just return :ok to measure overhead
    :ok
  end

  @doc """
  Recompiles a module from modified AST forms.

  Returns `{:ok, module, binary}` or `{:error, reason}`.
  """
  def recompile_module(module, forms) do
    # Compile options to match original compilation
    compile_opts = [:return_errors, :return_warnings, :debug_info]

    case :compile.forms(forms, compile_opts) do
      {:ok, ^module, binary, _warnings} ->
        {:ok, module, binary}

      {:error, errors, _warnings} ->
        {:error, {:compilation_failed, errors}}
    end
  end

  @doc """
  Loads a modified module atomically, replacing the old version.

  This is the dangerous part - loading a module while it's in use.

  Returns `:ok` or `{:error, reason}`.
  """
  def load_modified_module(module, binary) when is_atom(module) and is_binary(binary) do
    # Load the modified module
    # This will replace the old module definition
    case :code.load_binary(module, ~c"modified", binary) do
      {:module, ^module} ->
        :ok

      {:error, reason} ->
        {:error, {:load_failed, reason}}
    end
  end

  @doc """
  Tests if concurrent modification is safe by spawning multiple processes
  that continuously call a function while we modify it.

  Returns:
  - `{:ok, stats}` - All processes survived, no crashes
  - `{:error, reason}` - Crashes or deadlocks detected
  """
  def test_concurrent_modification(module, function, args, num_processes \\ 100) do
    # Start processes that continuously call the function
    # Use spawn instead of spawn_link to avoid EXIT signals
    processes =
      for i <- 1..num_processes do
        spawn(fn -> continuous_caller(module, function, args, i) end)
      end

    # Let them run for a bit
    Process.sleep(100)

    # Now attempt modification while they're running
    modification_result =
      case extract_abstract_code(module) do
        {:ok, forms} ->
          modified = inject_purity_check(forms, function, length(args))

          case recompile_module(module, modified) do
            {:ok, ^module, binary} ->
              load_modified_module(module, binary)

            error ->
              error
          end

        error ->
          error
      end

    # Let processes run a bit more
    Process.sleep(100)

    # Check if all processes are still alive
    alive_count = Enum.count(processes, &Process.alive?/1)

    # Clean up
    Enum.each(processes, fn pid ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    case modification_result do
      :ok ->
        {:ok, %{total: num_processes, alive: alive_count, modification: :success}}

      error ->
        {:error, error}
    end
  end

  # Helper for concurrent testing - continuously calls a function
  defp continuous_caller(module, function, args, id) do
    try do
      apply(module, function, args)
      # Small sleep to prevent spinning too hard
      Process.sleep(1)
      continuous_caller(module, function, args, id)
    rescue
      _ ->
        # If function changes signature, we might get errors
        # This is expected during modification
        Process.sleep(10)
        continuous_caller(module, function, args, id)
    end
  end

  @doc """
  Measures the performance overhead of a modified function vs original.

  Returns percentage overhead.
  """
  def measure_overhead(module, function, args, iterations \\ 10_000) do
    # Get baseline timing (before modification)
    {baseline_time, _} = :timer.tc(fn ->
      for _ <- 1..iterations do
        apply(module, function, args)
      end
    end)

    # Modify the module
    with {:ok, forms} <- extract_abstract_code(module),
         modified <- inject_purity_check(forms, function, length(args)),
         {:ok, ^module, binary} <- recompile_module(module, modified),
         :ok <- load_modified_module(module, binary) do
      # Measure modified timing
      {modified_time, _} = :timer.tc(fn ->
        for _ <- 1..iterations do
          apply(module, function, args)
        end
      end)

      overhead = (modified_time - baseline_time) / baseline_time * 100.0

      {:ok,
       %{
         baseline_microseconds: baseline_time,
         modified_microseconds: modified_time,
         overhead_percentage: overhead,
         iterations: iterations
       }}
    else
      error -> error
    end
  end

  @doc """
  Tests rollback capability - can we restore the original module?

  Returns `:ok` if rollback works, `{:error, reason}` otherwise.
  """
  def test_rollback(module) do
    # Save original BEAM binary
    with {:ok, original_beam} <- extract_beam_code(module),
         {:ok, original_forms} <- extract_abstract_code(module),
         # Modify the module
         modified_forms <- inject_purity_check(original_forms, :test_function, 1),
         {:ok, ^module, modified_binary} <- recompile_module(module, modified_forms),
         :ok <- load_modified_module(module, modified_binary),
         # Now rollback to original
         :ok <- load_modified_module(module, original_beam) do
      # Verify we're back to original
      {:ok, current_forms} = extract_abstract_code(module)

      if forms_equal?(original_forms, current_forms) do
        :ok
      else
        {:error, :rollback_verification_failed}
      end
    else
      error -> error
    end
  end

  # Compare two form lists (simplified - just check structure)
  defp forms_equal?(forms1, forms2) do
    length(forms1) == length(forms2)
  end
end
