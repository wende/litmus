defmodule Litmus do
  @moduledoc """
  Elixir wrapper for the PURITY static analyzer.

  Litmus provides purity analysis for Elixir code by wrapping the Erlang PURITY tool.
  It can analyze Elixir modules to determine which functions are pure (referentially
  transparent), which have side effects, and which depend on the execution environment.

  ## Purity Levels

  PURITY classifies functions into several categories, ordered from most pure to least pure:

  - `:pure` (p) - Referentially transparent, no side effects, no exceptions
  - `:exceptions` (e) - Side-effect free but may raise exceptions
  - `:dependent` (d) - Side-effect free but depends on execution environment (time, process dict, etc.)
  - `:nif` (n) - Calls a Native Implemented Function (behavior unknown, conservatively treated as impure)
  - `:side_effects` (s) - Has observable side effects (I/O, process operations, state mutation, etc.)

  **NIFs are a distinct purity level** between `:dependent` and `:side_effects`. While
  we cannot statically analyze native C/C++ code, we know that NIFs may be impure but
  don't necessarily have side effects. This allows for more nuanced reasoning about
  code that calls NIFs versus code that performs actual I/O.

  ## Usage

      # Analyze a single compiled module
      {:ok, results} = Litmus.analyze_module(MyModule)

      # Check if a specific function is pure
      Litmus.pure?(results, {MyModule, :my_function, 2})
      #=> true

      # Analyze multiple modules
      {:ok, results} = Litmus.analyze_modules([Mod1, Mod2, Mod3])

      # Analyze in parallel for better performance
      {:ok, results} = Litmus.analyze_parallel([Mod1, Mod2, Mod3])

  ## Important Notes

  - Modules must be compiled with `:debug_info` enabled for analysis
  - Dynamic dispatch and metaprogramming cannot be fully analyzed
  - Conservative assumptions are made for NIFs and unknown functions
  - Results represent compile-time static analysis, not runtime behavior
  """

  @type purity_level :: :pure | :exceptions | :dependent | :nif | :side_effects | :unknown
  @type purity_result :: %{
          mfa() => purity_level(),
          dependencies: list()
        }
  @type termination_level :: :terminating | :non_terminating | :unknown
  @type termination_result :: %{mfa() => termination_level()}
  @type combined_result :: %{mfa() => {purity_level(), termination_level()}}
  @type exception_result :: %{mfa() => Litmus.Exceptions.exception_info()}
  @type options :: keyword()

  # Purity result type from Erlang
  @type erl_purity :: {:p | :e | :d | :s | {:at_least, any()}, list()}

  @doc """
  Analyzes a single Elixir module and returns purity information.

  ## Parameters

    - `module` - The module atom (e.g., `MyApp.MyModule`)
    - `opts` - Optional keyword list of options (default: `[]`)

  ## Options

    - `:plt_path` - Path to PLT file for caching results
    - `:propagate` - Whether to propagate purity through dependencies (default: true)

  ## Returns

    - `{:ok, results}` - Map of `{module, function, arity}` to purity levels
    - `{:error, reason}` - If module cannot be analyzed

  ## Examples

      # Note: Enum, File, and IO use map literals that PURITY doesn't support
      # Use pre-2014 Erlang modules like :lists, :ordsets, :queue instead

      {:ok, results} = Litmus.analyze_module(:lists)
      Litmus.pure?(results, {:lists, :reverse, 1})
      #=> true
  """
  @spec analyze_module(module(), options()) :: {:ok, purity_result()} | {:error, term()}
  def analyze_module(module, opts \\ []) when is_atom(module) do
    case get_beam_path(module) do
      {:ok, beam_path} ->
        analyze_file(beam_path, opts)

      {:error, reason} ->
        {:error, {:beam_not_found, module, reason}}
    end
  end

  @doc """
  Analyzes multiple modules sequentially.

  This incrementally builds a lookup table containing purity information
  for all provided modules.

  ## Parameters

    - `modules` - List of module atoms
    - `opts` - Optional keyword list of options

  ## Returns

    - `{:ok, results}` - Combined purity results for all modules
    - `{:error, reason}` - If any module fails to analyze

  ## Examples

      {:ok, results} = Litmus.analyze_modules([:lists, :ordsets, :queue])
  """
  @spec analyze_modules(list(module()), options()) :: {:ok, purity_result()} | {:error, term()}
  def analyze_modules(modules, opts \\ []) when is_list(modules) do
    beam_paths =
      Enum.map(modules, fn mod ->
        case get_beam_path(mod) do
          {:ok, path} -> path
          {:error, reason} -> {:error, {mod, reason}}
        end
      end)

    case Enum.find(beam_paths, &match?({:error, _}, &1)) do
      {:error, {mod, reason}} ->
        {:error, {:beam_not_found, mod, reason}}

      nil ->
        analyze_files(beam_paths, opts)
    end
  end

  @doc """
  Analyzes multiple modules in parallel.

  Uses parallel processing (limited to CPU count) for faster analysis
  of large codebases.

  ## Parameters

    - `modules` - List of module atoms
    - `opts` - Optional keyword list of options

  ## Returns

    - `{:ok, results}` - Combined purity results for all modules
    - `{:error, reason}` - If any module fails to analyze

  ## Examples

      {:ok, results} = Litmus.analyze_parallel([:lists, :ordsets, :queue, :gb_sets])
  """
  @spec analyze_parallel(list(module()), options()) :: {:ok, purity_result()} | {:error, term()}
  def analyze_parallel(modules, opts \\ []) when is_list(modules) do
    beam_paths =
      Enum.map(modules, fn mod ->
        case get_beam_path(mod) do
          {:ok, path} -> path
          {:error, reason} -> {:error, {mod, reason}}
        end
      end)

    case Enum.find(beam_paths, &match?({:error, _}, &1)) do
      {:error, {mod, reason}} ->
        {:error, {:beam_not_found, mod, reason}}

      nil ->
        analyze_files_parallel(beam_paths, opts)
    end
  end

  @doc """
  Checks if a function is pure.

  This is a simple boolean test that only distinguishes between pure
  and impure functions. Any function missing from the results is
  considered impure.

  ## Parameters

    - `results` - Purity analysis results from `analyze_module/2` or similar
    - `mfa` - `{module, function, arity}` tuple

  ## Returns

    - `true` if the function is pure (referentially transparent)
    - `false` otherwise

  ## Examples

      {:ok, results} = Litmus.analyze_module(:lists)
      Litmus.pure?(results, {:lists, :reverse, 1})
      #=> true

      Litmus.pure?(results, {:io, :puts, 1})
      #=> false
  """
  @spec pure?(purity_result(), mfa()) :: boolean()
  def pure?(results, {_m, _f, _a} = mfa) when is_map(results) do
    erl_table = erlify_results(results)
    :purity.is_pure(mfa, erl_table)
  end

  @doc """
  Finds functions that are referenced but lack purity information.

  This is useful for identifying gaps in the analysis, such as:
  - Dynamically called functions
  - NIFs without purity annotations
  - Functions from unanalyzed modules

  ## Parameters

    - `results` - Purity analysis results

  ## Returns

    - `%{functions: [mfa()], primops: [tuple()]}` - Missing MFAs and primops

  ## Examples

      {:ok, results} = Litmus.analyze_module(MyModule)
      %{functions: mfas, primops: prims} = Litmus.find_missing(results)
  """
  @spec find_missing(purity_result()) :: %{functions: list(mfa()), primops: list()}
  def find_missing(results) when is_map(results) do
    erl_table = erlify_results(results)
    {mfas, primops} = :purity.find_missing(erl_table)
    %{functions: mfas, primops: primops}
  end

  @doc """
  Gets the purity level of a specific function.

  Returns the detailed purity classification for a function.

  ## Parameters

    - `results` - Purity analysis results
    - `mfa` - `{module, function, arity}` tuple

  ## Returns

    - `{:ok, purity_level}` - The purity level of the function
    - `:error` - If function is not in results

  ## Examples

      {:ok, results} = Litmus.analyze_module(:lists)
      {:ok, :pure} = Litmus.get_purity(results, {:lists, :map, 2})
  """
  @spec get_purity(purity_result(), mfa()) :: {:ok, purity_level()} | :error
  def get_purity(results, mfa) when is_map(results) do
    Map.fetch(results, mfa)
  end

  @doc """
  Checks if a function is whitelisted as pure in the Elixir standard library.

  This uses a manually curated whitelist of Elixir stdlib functions that are
  known to be pure. Unlike `pure?/2` which analyzes BEAM bytecode, this checks
  a pre-defined whitelist for maximum safety.

  **Whitelist Philosophy**: Only explicitly whitelisted functions return `true`.
  All other functions (including unknown ones) return `false` for maximum safety.

  ## Parameters

    - `mfa` - `{module, function, arity}` tuple

  ## Returns

    - `true` if the function is explicitly whitelisted as pure
    - `false` otherwise (unknown = impure for safety)

  ## Examples

      # Whitelisted pure functions
      Litmus.pure_stdlib?({Enum, :map, 2})
      #=> true

      Litmus.pure_stdlib?({Integer, :to_string, 1})
      #=> true

      # Not whitelisted (side effects)
      Litmus.pure_stdlib?({IO, :puts, 1})
      #=> false

      Litmus.pure_stdlib?({String, :to_atom, 1})
      #=> false

      # Unknown = impure (conservative)
      Litmus.pure_stdlib?({MyApp.Module, :my_func, 2})
      #=> false

  See `Litmus.Stdlib` for the full whitelist and documentation.
  """
  @spec pure_stdlib?(mfa()) :: boolean()
  def pure_stdlib?({_m, _f, _a} = mfa) do
    Litmus.Stdlib.whitelisted?(mfa)
  end

  @doc """
  Comprehensive purity check combining PURITY analysis and stdlib whitelist.

  This function checks both:
  1. PURITY static analysis results (if available)
  2. Elixir stdlib whitelist

  Returns `true` only if the function is confirmed pure by at least one method
  and not contradicted by the other.

  ## Strategy

  - If function is in PURITY results and marked pure → `true`
  - If function is whitelisted in stdlib → `true`
  - Otherwise → `false` (conservative)

  ## Parameters

    - `results` - Optional PURITY analysis results (can be `nil`)
    - `mfa` - `{module, function, arity}` tuple

  ## Returns

    - `true` if function is safe to optimize (proven pure)
    - `false` otherwise (unknown or impure)

  ## Examples

      # Pure by PURITY analysis
      {:ok, results} = Litmus.analyze_module(:lists)
      Litmus.safe_to_optimize?(results, {:lists, :reverse, 1})
      #=> true

      # Pure by whitelist (no analysis needed)
      Litmus.safe_to_optimize?(nil, {Enum, :map, 2})
      #=> true

      # Neither (impure)
      Litmus.safe_to_optimize?(nil, {IO, :puts, 1})
      #=> false
  """
  @spec safe_to_optimize?(purity_result() | nil, mfa()) :: boolean()
  def safe_to_optimize?(results, {_m, _f, _a} = mfa) do
    cond do
      # Check PURITY analysis first (if available)
      is_map(results) and pure?(results, mfa) ->
        true

      # Check stdlib whitelist
      pure_stdlib?(mfa) ->
        true

      # Conservative default: not safe
      true ->
        false
    end
  end

  @doc """
  Analyzes a single module for termination properties.

  Termination analysis determines whether functions are guaranteed to terminate
  (return or crash) versus potentially run forever (infinite loops, infinite
  recursion, blocking I/O, etc.).

  ## Termination Levels

  - `:terminating` - Function guaranteed to terminate
  - `:non_terminating` - Function may run forever
  - `:unknown` - Termination cannot be determined

  ## Key Insights

  - Recursive functions are non-terminating UNLESS they pass "reduced arguments"
  - All BIFs are assumed terminating (conservative)
  - Strongly connected components (mutual recursion) are non-terminating

  ## Parameters

    - `module` - The module atom to analyze
    - `opts` - Optional keyword list of options

  ## Returns

    - `{:ok, results}` - Map of `{module, function, arity}` to termination levels
    - `{:error, reason}` - If module cannot be analyzed

  ## Examples

      {:ok, results} = Litmus.analyze_termination(:lists)
      Litmus.terminates?(results, {:lists, :reverse, 1})
      #=> true
  """
  @spec analyze_termination(module(), options()) :: {:ok, termination_result()} | {:error, term()}
  def analyze_termination(module, opts \\ []) when is_atom(module) do
    case get_beam_path(module) do
      {:ok, beam_path} ->
        analyze_file_termination(beam_path, opts)

      {:error, reason} ->
        {:error, {:beam_not_found, module, reason}}
    end
  end

  @doc """
  Analyzes multiple modules for termination properties.

  ## Parameters

    - `modules` - List of module atoms
    - `opts` - Optional keyword list of options

  ## Returns

    - `{:ok, results}` - Combined termination results for all modules
    - `{:error, reason}` - If any module fails to analyze

  ## Examples

      {:ok, results} = Litmus.analyze_termination_modules([:lists, :ordsets])
  """
  @spec analyze_termination_modules(list(module()), options()) ::
          {:ok, termination_result()} | {:error, term()}
  def analyze_termination_modules(modules, opts \\ []) when is_list(modules) do
    beam_paths =
      Enum.map(modules, fn mod ->
        case get_beam_path(mod) do
          {:ok, path} -> path
          {:error, reason} -> {:error, {mod, reason}}
        end
      end)

    case Enum.find(beam_paths, &match?({:error, _}, &1)) do
      {:error, {mod, reason}} ->
        {:error, {:beam_not_found, mod, reason}}

      nil ->
        analyze_files_termination(beam_paths, opts)
    end
  end

  @doc """
  Performs combined purity and termination analysis.

  This runs both analyses together for maximum efficiency, analyzing each
  function once and returning both purity and termination information.

  ## Parameters

    - `module` - The module atom to analyze
    - `opts` - Optional keyword list of options

  ## Returns

    - `{:ok, results}` - Map of MFA to `{purity_level, termination_level}` tuples
    - `{:error, reason}` - If module cannot be analyzed

  ## Examples

      {:ok, results} = Litmus.analyze_both(:lists)
      results[{:lists, :reverse, 1}]
      #=> {:pure, :terminating}
  """
  @spec analyze_both(module(), options()) :: {:ok, combined_result()} | {:error, term()}
  def analyze_both(module, opts \\ []) when is_atom(module) do
    case get_beam_path(module) do
      {:ok, beam_path} ->
        analyze_file_both(beam_path, opts)

      {:error, reason} ->
        {:error, {:beam_not_found, module, reason}}
    end
  end

  @doc """
  Analyzes a single module for exceptions that can be raised.

  This tracks which specific exceptions (errors) can be raised by each function,
  as well as whether throw/exit can be used.

  ## Returns

    - `{:ok, results}` - Map of `{module, function, arity}` to exception info
    - `{:error, reason}` - If module cannot be analyzed

  ## Examples

      {:ok, results} = Litmus.analyze_exceptions(MyModule)
      info = results[{MyModule, :my_func, 1}]
      #=> %{errors: MapSet.new([ArgumentError]), non_errors: false}
  """
  @spec analyze_exceptions(module(), options()) :: {:ok, exception_result()} | {:error, term()}
  def analyze_exceptions(module, opts \\ []) when is_atom(module) do
    case get_beam_path(module) do
      {:ok, beam_path} ->
        analyze_file_exceptions(beam_path, opts)

      {:error, reason} ->
        {:error, {:beam_not_found, module, reason}}
    end
  end

  @doc """
  Checks if a function can raise a specific exception module.

  ## Parameters

    - `results` - Exception analysis results
    - `mfa` - `{module, function, arity}` tuple
    - `exception_module` - Exception module to check (e.g., `ArgumentError`)

  ## Returns

    - `true` if the function can raise that exception
    - `false` otherwise

  ## Examples

      {:ok, results} = Litmus.analyze_exceptions(MyModule)
      Litmus.can_raise?(results, {MyModule, :parse, 1}, ArgumentError)
      #=> true
  """
  @spec can_raise?(exception_result(), mfa(), module()) :: boolean()
  def can_raise?(results, mfa, exception_module) when is_map(results) do
    case Map.get(results, mfa) do
      nil -> false
      info -> Litmus.Exceptions.can_raise?(info, exception_module)
    end
  end

  @doc """
  Checks if a function can throw or exit.

  ## Parameters

    - `results` - Exception analysis results
    - `mfa` - `{module, function, arity}` tuple

  ## Returns

    - `true` if the function can use throw/exit
    - `false` otherwise

  ## Examples

      {:ok, results} = Litmus.analyze_exceptions(MyModule)
      Litmus.can_throw_or_exit?(results, {MyModule, :early_return, 1})
      #=> true
  """
  @spec can_throw_or_exit?(exception_result(), mfa()) :: boolean()
  def can_throw_or_exit?(results, mfa) when is_map(results) do
    case Map.get(results, mfa) do
      nil -> false
      info -> Litmus.Exceptions.can_throw_or_exit?(info)
    end
  end

  @doc """
  Gets exception information for a specific function.

  ## Parameters

    - `results` - Exception analysis results
    - `mfa` - `{module, function, arity}` tuple

  ## Returns

    - `{:ok, exception_info}` - The exception information
    - `:error` - If function is not in results

  ## Examples

      {:ok, results} = Litmus.analyze_exceptions(MyModule)
      {:ok, info} = Litmus.get_exceptions(results, {MyModule, :my_func, 1})
      info.errors
      #=> MapSet.new([ArgumentError, KeyError])
  """
  @spec get_exceptions(exception_result(), mfa()) ::
          {:ok, Litmus.Exceptions.exception_info()} | :error
  def get_exceptions(results, mfa) when is_map(results) do
    Map.fetch(results, mfa)
  end

  @doc """
  Checks if a function is guaranteed to terminate.

  ## Parameters

    - `results` - Termination analysis results
    - `mfa` - `{module, function, arity}` tuple

  ## Returns

    - `true` if the function is guaranteed to terminate
    - `false` otherwise (non-terminating or unknown)

  ## Examples

      {:ok, results} = Litmus.analyze_termination(:lists)
      Litmus.terminates?(results, {:lists, :map, 2})
      #=> true
  """
  @spec terminates?(termination_result(), mfa()) :: boolean()
  def terminates?(results, {_m, _f, _a} = mfa) when is_map(results) do
    Map.get(results, mfa) == :terminating
  end

  @doc """
  Gets the termination level of a specific function.

  ## Parameters

    - `results` - Termination analysis results
    - `mfa` - `{module, function, arity}` tuple

  ## Returns

    - `{:ok, termination_level}` - The termination level
    - `:error` - If function is not in results

  ## Examples

      {:ok, results} = Litmus.analyze_termination(:lists)
      {:ok, :terminating} = Litmus.get_termination(results, {:lists, :reverse, 1})
  """
  @spec get_termination(termination_result(), mfa()) :: {:ok, termination_level()} | :error
  def get_termination(results, mfa) when is_map(results) do
    Map.fetch(results, mfa)
  end

  ## Private Functions

  # Get the path to a module's .beam file
  defp get_beam_path(module) when is_atom(module) do
    case :code.which(module) do
      path when is_list(path) ->
        {:ok, List.to_string(path)}

      :non_existing ->
        {:error, :non_existing}

      other ->
        {:error, {:unexpected_code_which_result, other}}
    end
  end

  # Analyze a single .beam file
  defp analyze_file(beam_path, opts) do
    charlist_path = to_charlist(beam_path)
    erl_opts = elixirify_opts(opts)

    table = :purity_collect.file(charlist_path)
    propagated = :purity.propagate(table, erl_opts)

    {:ok, elixirify_results(propagated)}
  end

  # Analyze multiple files sequentially
  defp analyze_files(beam_paths, opts) do
    charlist_paths = Enum.map(beam_paths, &to_charlist/1)
    erl_opts = elixirify_opts(opts)

    table = :purity.files(charlist_paths)
    propagated = :purity.propagate(table, erl_opts)

    {:ok, elixirify_results(propagated)}
  end

  # Analyze multiple files in parallel
  defp analyze_files_parallel(beam_paths, opts) do
    charlist_paths = Enum.map(beam_paths, &to_charlist/1)
    erl_opts = elixirify_opts(opts)

    table = :purity.pfiles(charlist_paths)
    propagated = :purity.propagate(table, erl_opts)

    {:ok, elixirify_results(propagated)}
  end

  # Convert Elixir opts to Erlang format
  defp elixirify_opts(opts) do
    Enum.map(opts, fn
      {:plt_path, path} when is_binary(path) ->
        {:plt, to_charlist(path)}

      {key, value} ->
        {key, value}
    end)
  end

  # Convert Erlang dict results to Elixir map
  defp elixirify_results(erl_dict) do
    :dict.fold(
      fn mfa, purity_tuple, acc ->
        Map.put(acc, mfa, elixirify_purity(purity_tuple))
      end,
      %{},
      erl_dict
    )
  end

  # Convert Erlang purity result to Elixir atom
  defp elixirify_purity({purity, _deps}) do
    case purity do
      :p -> :pure
      :e -> :exceptions
      :d -> :dependent
      :n -> :nif
      :s -> :side_effects
      {:at_least, _} -> :unknown
      _ -> :unknown
    end
  end

  # Convert Elixir map back to Erlang dict for PURITY functions
  defp erlify_results(results) when is_map(results) do
    Enum.reduce(results, :dict.new(), fn {mfa, purity}, acc ->
      erl_purity = erlify_purity(purity)
      :dict.store(mfa, erl_purity, acc)
    end)
  end

  # Convert Elixir purity level back to Erlang tuple format
  defp erlify_purity(purity) do
    erl_atom =
      case purity do
        :pure -> :p
        :exceptions -> :e
        :dependent -> :d
        :nif -> :n
        :side_effects -> :s
        :unknown -> {:at_least, :s}
        _ -> {:at_least, :s}
      end

    {erl_atom, []}
  end

  # Analyze a single file for termination
  defp analyze_file_termination(beam_path, opts) do
    charlist_path = to_charlist(beam_path)
    erl_opts = elixirify_opts(opts) ++ [termination: true]

    table = :purity_collect.file(charlist_path)
    propagated = :purity_analyse.propagate_termination(table, erl_opts)

    {:ok, elixirify_termination_results(propagated)}
  end

  # Analyze multiple files for termination
  defp analyze_files_termination(beam_paths, opts) do
    charlist_paths = Enum.map(beam_paths, &to_charlist/1)
    erl_opts = elixirify_opts(opts) ++ [termination: true]

    table = :purity.files(charlist_paths)
    propagated = :purity_analyse.propagate_termination(table, erl_opts)

    {:ok, elixirify_termination_results(propagated)}
  end

  # Analyze a single file for both purity and termination
  defp analyze_file_both(beam_path, opts) do
    charlist_path = to_charlist(beam_path)
    erl_opts = elixirify_opts(opts) ++ [both: true]

    table = :purity_collect.file(charlist_path)
    propagated = :purity_analyse.propagate_both(table, erl_opts)

    {:ok, elixirify_both_results(propagated)}
  end

  # Convert Erlang dict termination results to Elixir map
  defp elixirify_termination_results(erl_dict) do
    :dict.fold(
      fn mfa, {termination, _deps}, acc ->
        Map.put(acc, mfa, elixirify_termination(termination))
      end,
      %{},
      erl_dict
    )
  end

  # Convert Erlang termination result to Elixir atom
  defp elixirify_termination(termination) do
    case termination do
      :p -> :terminating
      :s -> :non_terminating
      {:at_least, :p} -> :unknown
      {:at_least, :s} -> :non_terminating
      _ -> :unknown
    end
  end

  # Convert combined purity + termination results to Elixir map
  defp elixirify_both_results(erl_dict) do
    :dict.fold(
      fn mfa, {level, _deps}, acc ->
        # Extract both purity and termination from the combined result
        purity = elixirify_purity({level, []})
        termination = elixirify_termination(level)
        Map.put(acc, mfa, {purity, termination})
      end,
      %{},
      erl_dict
    )
  end

  # Analyze a single file for exceptions
  defp analyze_file_exceptions(beam_path, _opts) do
    charlist_path = to_charlist(beam_path)

    # Get the raw dependency table from PURITY
    table = :purity_collect.file(charlist_path)

    # Extract exception information from dependencies
    exception_map =
      :dict.fold(
        fn mfa, deps, acc ->
          exception_info = extract_exceptions_from_deps(mfa, deps)
          Map.put(acc, mfa, exception_info)
        end,
        %{},
        table
      )

    # Propagate exceptions through call graph
    propagated = propagate_exceptions(exception_map, table)

    # Analyze try/catch blocks to find caught exceptions
    case Litmus.TryCatch.analyze_beam(beam_path) do
      {:ok, caught_map} ->
        # Subtract caught exceptions from propagated exceptions
        final = subtract_caught_exceptions(propagated, caught_map)
        {:ok, final}

      {:error, _reason} ->
        # If try/catch analysis fails, return propagated results (conservative)
        {:ok, propagated}
    end
  end

  # Subtract caught exceptions from propagated exceptions
  defp subtract_caught_exceptions(exception_map, caught_map) do
    Map.new(exception_map, fn {mfa, raised_exceptions} ->
      case Map.get(caught_map, mfa) do
        nil ->
          # Function doesn't catch anything
          {mfa, raised_exceptions}

        caught_exceptions ->
          # Subtract what's caught from what's raised
          remaining = Litmus.Exceptions.subtract(raised_exceptions, caught_exceptions)
          {mfa, remaining}
      end
    end)
  end

  # Extract exception information from a function's dependency list
  defp extract_exceptions_from_deps(mfa, deps) when is_list(deps) do
    # Check stdlib whitelist first
    case Litmus.Stdlib.get_exception_info(mfa) do
      nil ->
        # Not in stdlib, analyze dependencies
        analyze_deps_for_exceptions(deps)

      stdlib_info ->
        # Use stdlib info
        stdlib_info
    end
  end

  # Analyze dependencies to find exception-raising calls
  defp analyze_deps_for_exceptions(deps) do
    Enum.reduce(deps, Litmus.Exceptions.empty(), fn dep, acc ->
      case dep do
        # Remote call: check if it's erlang:error/throw/exit
        {:remote, {module, function, arity}, _args} ->
          exception_info = check_exception_call(module, function, arity)
          merged = Litmus.Exceptions.merge(acc, exception_info)

          # Also check stdlib whitelist if not an exception primitive
          case Litmus.Stdlib.get_exception_info({module, function, arity}) do
            nil -> merged
            info -> Litmus.Exceptions.merge(merged, info)
          end

        # Check stdlib whitelist for remote calls
        {:remote, mfa, _args} when is_tuple(mfa) and tuple_size(mfa) == 3 ->
          exception_info = check_exception_call(elem(mfa, 0), elem(mfa, 1), elem(mfa, 2))
          merged = Litmus.Exceptions.merge(acc, exception_info)

          case Litmus.Stdlib.get_exception_info(mfa) do
            nil -> merged
            info -> Litmus.Exceptions.merge(merged, info)
          end

        # Local calls - will be handled by propagation
        # Primops, etc - ignore for now
        _ ->
          acc
      end
    end)
  end

  # Check if a call is to erlang:error/throw/exit
  defp check_exception_call(:erlang, :error, arity) when arity in [1, 2] do
    # erlang:error raises exceptions, but we can't determine which one
    # from just the dependency list (would need to analyze arguments)
    Litmus.Exceptions.error_dynamic()
  end

  defp check_exception_call(:erlang, :throw, 1) do
    Litmus.Exceptions.non_error()
  end

  defp check_exception_call(:erlang, :exit, 1) do
    Litmus.Exceptions.non_error()
  end

  defp check_exception_call(_module, _function, _arity) do
    Litmus.Exceptions.empty()
  end

  # Propagate exceptions through the call graph until fixpoint
  defp propagate_exceptions(exception_map, table) do
    # Build call graph: MFA -> [called MFAs]
    call_graph = build_call_graph(table)

    # Iterate until fixpoint
    iterate_exception_propagation(exception_map, call_graph)
  end

  # Build call graph from dependency table
  defp build_call_graph(table) do
    :dict.fold(
      fn mfa, deps, acc ->
        callees = extract_called_mfas(deps)
        Map.put(acc, mfa, callees)
      end,
      %{},
      table
    )
  end

  # Extract all called MFAs from a dependency list
  defp extract_called_mfas(deps) when is_list(deps) do
    Enum.flat_map(deps, fn dep ->
      case dep do
        # Local call (within same module)
        {:local, {module, function, arity}, _args} ->
          [{module, function, arity}]

        # Local call with MFA tuple
        {:local, mfa, _args} when is_tuple(mfa) and tuple_size(mfa) == 3 ->
          [mfa]

        # Remote call with explicit MFA tuple
        {:remote, {module, function, arity}, _args} ->
          [{module, function, arity}]

        # Remote call with MFA tuple
        {:remote, mfa, _args} when is_tuple(mfa) and tuple_size(mfa) == 3 ->
          [mfa]

        # Primops, etc - ignore for call graph
        _ ->
          []
      end
    end)
    |> Enum.uniq()
  end

  # Iterate exception propagation until fixpoint
  defp iterate_exception_propagation(exception_map, call_graph) do
    # Compute new exception map by merging with callee exceptions
    new_map =
      Map.new(exception_map, fn {mfa, direct_exceptions} ->
        # Get all functions called by this function
        callees = Map.get(call_graph, mfa, [])

        # Merge exceptions from all callees
        callee_exceptions =
          callees
          |> Enum.map(fn callee ->
            # Check if callee is in our analysis results
            case Map.get(exception_map, callee) do
              nil ->
                # Not in our module, check stdlib whitelist
                Litmus.Stdlib.get_exception_info(callee) || Litmus.Exceptions.empty()

              info ->
                info
            end
          end)
          |> Enum.reduce(Litmus.Exceptions.empty(), &Litmus.Exceptions.merge/2)

        # Merge direct exceptions with callee exceptions
        merged = Litmus.Exceptions.merge(direct_exceptions, callee_exceptions)
        {mfa, merged}
      end)

    # Check if we reached fixpoint
    if maps_equal?(new_map, exception_map) do
      new_map
    else
      # Continue iterating
      iterate_exception_propagation(new_map, call_graph)
    end
  end

  # Check if two exception maps are equal
  defp maps_equal?(map1, map2) do
    map1 == map2
  end
end
