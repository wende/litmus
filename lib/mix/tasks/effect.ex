defmodule Mix.Tasks.Effect do
  @moduledoc """
  Analyzes an Elixir file and displays all functions with their inferred effects and exceptions.

  ## Usage

      mix effect path/to/file.ex

  ## Options

      --verbose, -v     Show detailed analysis including type information
      --json            Output results in JSON format
      --exceptions      Include exception analysis
      --purity          Include purity analysis from PURITY analyzer

  ## Examples

      # Basic effect analysis
      mix effect lib/my_module.ex

      # Verbose output with types
      mix effect lib/my_module.ex --verbose

      # Include exception tracking
      mix effect lib/my_module.ex --exceptions

      # JSON output for tooling
      mix effect lib/my_module.ex --json
  """

  use Mix.Task

  alias Litmus.Analyzer.ASTWalker
  alias Litmus.Types.{Core, Effects}

  @shortdoc "Analyzes effects and exceptions in an Elixir file"

  @impl Mix.Task
  def run(args) do
    # Parse options
    {opts, paths, _} = OptionParser.parse(args,
      switches: [verbose: :boolean, json: :boolean, exceptions: :boolean, purity: :boolean],
      aliases: [v: :verbose]
    )

    case paths do
      [] ->
        Mix.shell().error("Error: No file path provided")
        Mix.shell().info("\nUsage: mix effect path/to/file.ex")
        Mix.shell().info("\nRun 'mix help effect' for more information")
        exit({:shutdown, 1})

      [path | _] ->
        analyze_file(path, opts)
    end
  end

  defp analyze_file(path, opts) do
    unless File.exists?(path) do
      Mix.shell().error("Error: File not found: #{path}")
      exit({:shutdown, 1})
    end

    Mix.shell().info("Analyzing: #{path}\n")

    # Parse source file to AST then analyze
    result = case File.read(path) do
      {:ok, source} ->
        case Code.string_to_quoted(source, file: path, line: 1) do
          {:ok, ast} ->
            ASTWalker.analyze_ast(ast)

          {:error, {line, error, _}} ->
            {:error, {:parse_error, line, error}}
        end

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end

    case result do
      {:ok, analysis} ->
        if opts[:json] do
          output_json(analysis, opts)
        else
          output_text(analysis, opts)
        end

      {:error, {:parse_error, line, error}} ->
        Mix.shell().error("Parse error at line #{line}: #{error}")
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("Analysis failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp output_text(result, opts) do
    module = result.module
    functions = result.functions
    errors = result.errors

    # Header
    Mix.shell().info("═══════════════════════════════════════════════════════════")
    Mix.shell().info("Module: #{inspect(module)}")
    Mix.shell().info("═══════════════════════════════════════════════════════════\n")

    if Enum.empty?(functions) do
      Mix.shell().info("No functions found in module.\n")
    else
      # Sort functions by name and arity
      sorted_functions = Enum.sort_by(functions, fn {{_m, f, a}, _} -> {f, a} end)

      Enum.each(sorted_functions, fn {{_m, name, arity}, analysis} ->
        display_function(name, arity, analysis, opts)
      end)
    end

    # Display errors if any
    unless Enum.empty?(errors) do
      Mix.shell().info("\n#{IO.ANSI.yellow()}⚠ Warnings/Errors:#{IO.ANSI.reset()}")
      Mix.shell().info("═══════════════════════════════════════════════════════════\n")

      Enum.each(errors, fn error ->
        {_mod, func, line} = error.location
        Mix.shell().info("  #{IO.ANSI.red()}•#{IO.ANSI.reset()} #{func} (line #{line})")
        Mix.shell().info("    #{error.message}\n")
      end)
    end

    # Summary
    Mix.shell().info("\n═══════════════════════════════════════════════════════════")

    {pure_count, lambda_count, effectful_count} = count_by_purity(functions)
    total = pure_count + lambda_count + effectful_count

    Mix.shell().info("Summary: #{total} functions analyzed")
    Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} Pure: #{pure_count}")
    Mix.shell().info("  #{IO.ANSI.cyan()}λ#{IO.ANSI.reset()} Lambda-dependent: #{lambda_count}")
    Mix.shell().info("  #{IO.ANSI.yellow()}⚡#{IO.ANSI.reset()} Effectful: #{effectful_count}")

    unless Enum.empty?(errors) do
      Mix.shell().info("  #{IO.ANSI.red()}⚠#{IO.ANSI.reset()} Errors: #{length(errors)}")
    end

    Mix.shell().info("═══════════════════════════════════════════════════════════\n")
  end

  defp display_function(name, arity, analysis, opts) do
    visibility = if analysis[:visibility] == :defp, do: " (private)", else: ""

    # Function header
    Mix.shell().info("#{IO.ANSI.cyan()}#{name}/#{arity}#{IO.ANSI.reset()}#{visibility}")
    Mix.shell().info("  #{String.duplicate("─", 55)}")

    # Effect information - use compact format
    effect = analysis.effect
    compact_effect = Core.to_compact_effect(effect)

    is_pure = Effects.is_pure?(effect)
    is_lambda_dependent = compact_effect == :u

    purity_indicator = cond do
      is_pure ->
        "#{IO.ANSI.green()}✓ Pure#{IO.ANSI.reset()}"
      is_lambda_dependent ->
        "#{IO.ANSI.cyan()}λ Lambda-dependent#{IO.ANSI.reset()}"
      true ->
        "#{IO.ANSI.yellow()}⚡ Effectful#{IO.ANSI.reset()}"
    end

    Mix.shell().info("  #{purity_indicator}")
    Mix.shell().info("  Effect: #{Core.format_compact_effect(compact_effect)}")

    # Type information in verbose mode
    if opts[:verbose] do
      type_str = Core.format_type(analysis.type)
      Mix.shell().info("  Type: #{type_str}")
      Mix.shell().info("  Return: #{Core.format_type(analysis.return_type)}")
    end

    # Function calls (filtered)
    filtered_calls = filter_noise_calls(analysis.calls)

    unless Enum.empty?(filtered_calls) do
      Mix.shell().info("  Calls:")
      filtered_calls
      |> Enum.take(5)  # Limit to first 5 calls
      |> Enum.each(fn {m, f, a} ->
        # Try to get effect from registry, default to unknown for local functions
        call_effect = try do
          Effects.from_mfa({m, f, a})
        rescue
          _ -> {:effect_unknown}  # Local functions default to unknown
        end

        call_compact = Core.to_compact_effect(call_effect)
        call_indicator = cond do
          Effects.is_pure?(call_effect) ->
            IO.ANSI.green() <> "→" <> IO.ANSI.reset()
          call_compact == :u ->
            IO.ANSI.cyan() <> "λ" <> IO.ANSI.reset()
          true ->
            IO.ANSI.yellow() <> "⚡" <> IO.ANSI.reset()
        end
        # Strip "Elixir." prefix from module name
        module_name = m |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
        Mix.shell().info("    #{call_indicator} #{module_name}.#{f}/#{a}")
      end)

      if length(filtered_calls) > 5 do
        Mix.shell().info("    ... and #{length(filtered_calls) - 5} more")
      end
    end

    # Exception analysis if requested
    if opts[:exceptions] do
      display_exception_info(name, arity, opts)
    end

    Mix.shell().info("")
  end

  defp display_exception_info(_name, _arity, _opts) do
    # Try to get exception information from the existing analysis
    # This would integrate with Litmus.analyze_exceptions if available
    Mix.shell().info("  #{IO.ANSI.faint()}(Exception analysis: run with compiled module)#{IO.ANSI.reset()}")
  end

  defp filter_noise_calls(calls) do
    # Stateful Kernel functions that should be shown
    stateful_kernel_functions = [
      :send, :spawn, :spawn_link, :spawn_monitor, :apply, :exit,
      :self, :make_ref, :raise, :reraise, :throw
    ]

    # Filter out noise
    Enum.reject(calls, fn {module, function, _arity} ->
      # Keep all non-Kernel calls
      if module != Kernel do
        false
      else
        # For Kernel, only hide pure structural calls
        function not in stateful_kernel_functions and
        is_kernel_noise_function?(function)
      end
    end)
  end

  # Check if a Kernel function is noise (structural/pure operations)
  defp is_kernel_noise_function?(function) do
    noise_patterns = [
      # Operators
      :+, :-, :*, :/, :==, :!=, :<, :>, :<=, :>=, :===, :!==,
      :and, :or, :not, :&&, :||, :!,
      :++, :--, :<>, :in,

      # Assignment and structural
      :=, :., :.., :"::", :"|>", :".", :__aliases__, :__block__,

      # Binary operations
      :<<>>,

      # Type checks and conversions
      :is_atom, :is_binary, :is_bitstring, :is_boolean, :is_float,
      :is_function, :is_integer, :is_list, :is_map, :is_number,
      :is_nil, :is_pid, :is_port, :is_reference, :is_tuple,
      :to_string, :to_charlist,

      # Pure accessors and inspectors
      :hd, :tl, :length, :elem, :get_in, :put_in, :update_in,
      :byte_size, :bit_size, :tuple_size, :map_size,

      # Lambda/function
      :fn, :&, :->,

      # Pure Kernel functions
      :abs, :div, :rem, :max, :min, :round, :trunc, :ceil, :floor,
      :inspect, :match?
    ]

    function in noise_patterns
  end

  defp count_by_purity(functions) do
    Enum.reduce(functions, {0, 0, 0}, fn {_mfa, analysis}, {pure, lambda, effectful} ->
      compact_effect = Core.to_compact_effect(analysis.effect)
      cond do
        Effects.is_pure?(analysis.effect) ->
          {pure + 1, lambda, effectful}
        compact_effect == :u ->
          {pure, lambda + 1, effectful}
        true ->
          {pure, lambda, effectful + 1}
      end
    end)
  end

  defp output_json(result, _opts) do
    # Convert to JSON-friendly format
    json_result = %{
      module: inspect(result.module),
      functions: Enum.map(result.functions, fn {{m, f, a}, analysis} ->
        %{
          module: inspect(m),
          name: f,
          arity: a,
          effect: Core.format_effect(analysis.effect),
          compact_effect: Core.to_compact_effect(analysis.effect),
          effect_labels: Effects.to_list(analysis.effect),
          is_pure: Effects.is_pure?(analysis.effect),
          type: Core.format_type(analysis.type),
          return_type: Core.format_type(analysis.return_type),
          visibility: analysis[:visibility] || :def,
          calls: Enum.map(analysis.calls, fn {cm, cf, ca} ->
            %{module: inspect(cm), function: cf, arity: ca}
          end),
          line: analysis.line
        }
      end),
      errors: Enum.map(result.errors, fn error ->
        {mod, func, line} = error.location
        %{
          type: error.type,
          message: error.message,
          location: %{module: inspect(mod), function: func, line: line}
        }
      end)
    }

    Mix.shell().info(Jason.encode!(json_result, pretty: true))
  end
end
