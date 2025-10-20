defmodule Litmus.Analyzer.CallGraphTracer do
  @moduledoc """
  Traces function calls through to their leaf BIFs (Built-In Functions).

  This module recursively analyzes Elixir and Erlang stdlib functions to discover
  the actual Erlang BIFs that cause effects, ignoring wrapper functions.

  For example:
  - File.write!/2 → File.write/2 → :file.write_file/2 (BIF)
  - IO.puts/1 → :io.put_chars/2 (BIF)
  """

  alias Litmus.Analyzer.EffectTracker

  @doc """
  Traces a function to its leaf BIFs.

  Returns `{:ok, [leaf_bif_mfas]}` or `{:error, reason}`.

  ## Options

  - `:max_depth` - Maximum recursion depth (default: 10)
  - `:timeout` - Timeout per function in milliseconds (default: 5000)

  ## Examples

      iex> trace_to_leaf(File, :write!, 2)
      {:ok, [{:file, :write_file, 2}]}

      iex> trace_to_leaf(IO, :puts, 1)
      {:ok, [{:io, :put_chars, 2}]}
  """
  def trace_to_leaf(module, function, arity, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 10)
    timeout = Keyword.get(opts, :timeout, 5000)

    task =
      Task.async(fn ->
        trace_to_leaf_impl({module, function, arity}, MapSet.new(), 0, max_depth)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  # Internal recursive tracer with cycle detection and depth limiting
  defp trace_to_leaf_impl(mfa, visited, depth, max_depth) do
    cond do
      # Hit depth limit - treat as leaf
      depth > max_depth ->
        {:ok, [mfa]}

      # Cycle detected - treat as leaf
      MapSet.member?(visited, mfa) ->
        {:ok, [mfa]}

      true ->
        visited = MapSet.put(visited, mfa)
        {module, function, arity} = mfa

        cond do
          # Check if it's a BIF
          is_bif?(module, function, arity) ->
            {:ok, [mfa]}

          # Try to get the function implementation and trace it
          true ->
            case get_function_calls(module, function, arity) do
              {:ok, [_ | _] = calls} ->
                # Recursively trace all calls and collect leaf BIFs
                results =
                  Enum.map(calls, fn call_mfa ->
                    trace_to_leaf_impl(call_mfa, visited, depth + 1, max_depth)
                  end)

                # Check if all traces succeeded
                if Enum.all?(results, fn res -> match?({:ok, _}, res) end) do
                  # Collect and deduplicate all leaf BIFs
                  leaves =
                    results
                    |> Enum.flat_map(fn {:ok, bifs} -> bifs end)
                    |> Enum.uniq()

                  {:ok, leaves}
                else
                  # Some trace failed, treat current function as leaf
                  {:ok, [mfa]}
                end

              {:ok, []} ->
                # No calls found - this is a leaf (might be pure or unknown)
                {:ok, [mfa]}

              {:error, _reason} ->
                # Can't analyze - treat as leaf
                {:ok, [mfa]}
            end
        end
    end
  end

  @doc """
  Checks if an MFA is a BIF (Built-In Function).

  Uses `:erlang.is_builtin/3` and known BIF patterns.
  """
  def is_bif?(module, function, arity) do
    cond do
      # Use Erlang's is_builtin check
      :erlang.is_builtin(module, function, arity) ->
        true

      # Known BIF modules
      module in [:erlang, :erts_internal, :prim_file, :prim_inet, :prim_zip] ->
        true

      # Known Erlang modules with BIFs
      # (Some functions in these modules are BIFs, but not all)
      module in [:lists, :maps, :binary, :unicode, :re] ->
        # For now, conservatively treat as BIFs
        # TODO: Could refine this with more specific checks
        true

      # Elixir modules are never BIFs
      is_elixir_module?(module) ->
        false

      # For other Erlang modules, check if we can find source
      # If no source available, likely a BIF
      true ->
        case get_module_source(module) do
          # Has source, not a BIF
          {:ok, _source} -> false
          # No source, likely a BIF
          {:error, _} -> true
        end
    end
  end

  @doc """
  Extracts all function calls from a function implementation.

  Returns `{:ok, [called_mfas]}` or `{:error, reason}`.

  First tries BEAM abstract code (fast, works for Erlang/Elixir),
  then falls back to AST parsing for source files.
  """
  def get_function_calls(module, function, arity) do
    case get_function_from_beam(module, function, arity) do
      {:ok, calls} when is_list(calls) ->
        # BEAM abstract code returned calls directly
        {:ok, calls}

      {:error, _} ->
        # Fall back to AST-based extraction
        case get_function_ast(module, function, arity) do
          {:ok, ast} ->
            calls = EffectTracker.extract_calls(ast)
            {:ok, calls}

          error ->
            error
        end
    end
  end

  @doc """
  Gets the AST for a specific function.

  First tries to extract from BEAM abstract code, then falls back to source parsing.
  """
  def get_function_ast(module, function, arity) do
    # First try BEAM abstract code (works for Erlang and compiled Elixir)
    case get_function_from_beam(module, function, arity) do
      {:ok, _ast} = success ->
        success

      {:error, _} ->
        # Fall back to source parsing
        case get_module_source(module) do
          {:ok, source} ->
            case Code.string_to_quoted(source) do
              {:ok, ast} ->
                case extract_function_from_module_ast(ast, function, arity) do
                  {:ok, func_ast} -> {:ok, func_ast}
                  :not_found -> {:error, :function_not_found}
                end

              {:error, reason} ->
                {:error, {:parse_error, reason}}
            end

          error ->
            error
        end
    end
  end

  @doc """
  Extracts function calls from BEAM file abstract code.

  This works for both Elixir and Erlang modules by parsing the Erlang abstract format.
  """
  def get_function_from_beam(module, function, arity) do
    case :code.which(module) do
      :non_existing ->
        {:error, :module_not_found}

      :preloaded ->
        {:error, :preloaded}

      beam_path when is_list(beam_path) ->
        case :beam_lib.chunks(beam_path, [:abstract_code]) do
          {:ok, {^module, [{:abstract_code, {_vsn, abstract_code}}]}} ->
            extract_calls_from_abstract_code(abstract_code, function, arity)

          _ ->
            {:error, :no_abstract_code}
        end
    end
  end

  # Extract calls from Erlang abstract code format
  defp extract_calls_from_abstract_code(abstract_code, target_function, target_arity) do
    # First, get the module name from the abstract code
    module =
      Enum.find_value(abstract_code, fn
        {:attribute, _line, :module, mod} -> mod
        _ -> nil
      end)

    # Find the target function in the abstract code
    function_form =
      Enum.find(abstract_code, fn
        {:function, _line, ^target_function, ^target_arity, _clauses} -> true
        _ -> false
      end)

    case function_form do
      nil ->
        {:error, :function_not_found}

      {:function, _line, _name, _arity, clauses} ->
        # Extract all remote and local calls from the function clauses
        calls = extract_calls_from_clauses(clauses, module)
        {:ok, calls}
    end
  end

  # Extract MFA calls from function clauses (Erlang abstract format)
  defp extract_calls_from_clauses(clauses, module) do
    clauses
    |> Enum.flat_map(&extract_calls_from_clause(&1, module))
    |> Enum.uniq()
  end

  defp extract_calls_from_clause({:clause, _line, _patterns, _guards, body}, module) do
    extract_calls_from_body(body, module)
  end

  defp extract_calls_from_body(body, module) when is_list(body) do
    Enum.flat_map(body, &extract_calls_from_expr(&1, module))
  end

  # Extract calls from a single expression
  defp extract_calls_from_expr(expr, module) do
    case expr do
      # Remote call: module:function(args)
      {:call, _line, {:remote, _line2, {:atom, _line3, call_module}, {:atom, _line4, function}},
       args} ->
        arity = length(args)
        nested_calls = Enum.flat_map(args, &extract_calls_from_expr(&1, module))
        [{call_module, function, arity} | nested_calls]

      # Local call: function(args) - resolve to current module
      {:call, _line, {:atom, _line2, function}, args} ->
        arity = length(args)
        nested_calls = Enum.flat_map(args, &extract_calls_from_expr(&1, module))
        [{module, function, arity} | nested_calls]

      # Variable call: Var(args) - can't resolve statically
      {:call, _line, _var, args} ->
        Enum.flat_map(args, &extract_calls_from_expr(&1, module))

      # Match expression
      {:match, _line, left, right} ->
        extract_calls_from_expr(left, module) ++ extract_calls_from_expr(right, module)

      # Case expression
      {:case, _line, expr, clauses} ->
        expr_calls = extract_calls_from_expr(expr, module)
        clause_calls = Enum.flat_map(clauses, &extract_calls_from_clause(&1, module))
        expr_calls ++ clause_calls

      # If expression
      {:if, _line, clauses} ->
        Enum.flat_map(clauses, &extract_calls_from_clause(&1, module))

      # Block
      {:block, _line, exprs} ->
        Enum.flat_map(exprs, &extract_calls_from_expr(&1, module))

      # Tuple
      {:tuple, _line, elements} ->
        Enum.flat_map(elements, &extract_calls_from_expr(&1, module))

      # List
      {:cons, _line, head, tail} ->
        extract_calls_from_expr(head, module) ++ extract_calls_from_expr(tail, module)

      # Binary/string
      {:bin, _line, _elements} ->
        []

      # Operators (treated as calls in some cases)
      {:op, _line, _op, left, right} ->
        extract_calls_from_expr(left, module) ++ extract_calls_from_expr(right, module)

      {:op, _line, _op, operand} ->
        extract_calls_from_expr(operand, module)

      # Literals
      {:atom, _line, _value} ->
        []

      {:integer, _line, _value} ->
        []

      {:float, _line, _value} ->
        []

      {:string, _line, _value} ->
        []

      {:char, _line, _value} ->
        []

      {nil, _line} ->
        []

      # Variables
      {:var, _line, _name} ->
        []

      # Catch/try
      {:try, _line, body, _case_clauses, catch_clauses, after_body} ->
        body_calls = Enum.flat_map(body, &extract_calls_from_expr(&1, module))
        catch_calls = Enum.flat_map(catch_clauses, &extract_calls_from_clause(&1, module))
        after_calls = Enum.flat_map(after_body, &extract_calls_from_expr(&1, module))
        body_calls ++ catch_calls ++ after_calls

      # Receive
      {:receive, _line, clauses} ->
        Enum.flat_map(clauses, &extract_calls_from_clause(&1, module))

      # Fun/lambda
      {:fun, _line, {:clauses, clauses}} ->
        Enum.flat_map(clauses, &extract_calls_from_clause(&1, module))

      # Unknown/unsupported expression
      _ ->
        []
    end
  end

  @doc """
  Gets the source code for a module.
  """
  def get_module_source(module) do
    case :code.which(module) do
      :non_existing ->
        {:error, :module_not_found}

      :preloaded ->
        # Preloaded modules (erlang BIFs) have no source
        {:error, :preloaded}

      beam_path when is_list(beam_path) ->
        # Try to get source from BEAM debug info
        case :beam_lib.chunks(beam_path, [:abstract_code]) do
          {:ok, {^module, [{:abstract_code, {_vsn, _abstract_code}}]}} ->
            # Convert Erlang abstract format to source
            # This is complex - for now, we'll use a simpler approach
            {:error, :erlang_abstract_format}

          _ ->
            # Try to find Elixir source file
            get_elixir_source_file(module)
        end
    end
  end

  # Helper to get Elixir source file
  defp get_elixir_source_file(module) do
    if is_elixir_module?(module) do
      module_name = module |> Atom.to_string() |> String.replace("Elixir.", "")

      # Try standard locations
      candidates = [
        # Standard lib/ structure
        "lib/#{Macro.underscore(module_name)}.ex",

        # Stdlib location (in Elixir installation)
        elixir_lib_path(module_name)
      ]

      Enum.find_value(candidates, {:error, :source_not_found}, fn path ->
        if File.exists?(path) do
          case File.read(path) do
            {:ok, content} -> {:ok, content}
            error -> error
          end
        else
          nil
        end
      end)
    else
      {:error, :not_elixir_module}
    end
  end

  # Get path to Elixir stdlib source
  defp elixir_lib_path(module_name) do
    elixir_src = Path.join([:code.lib_dir(:elixir), "lib"])
    Path.join(elixir_src, "#{Macro.underscore(module_name)}.ex")
  end

  # Helper to check if module is an Elixir module
  defp is_elixir_module?(module) do
    module
    |> Atom.to_string()
    |> String.starts_with?("Elixir.")
  end

  # Extract a specific function from a module AST
  defp extract_function_from_module_ast(ast, target_function, target_arity) do
    result =
      Macro.prewalk(ast, nil, fn
        # Match def/defp with the target function name and arity
        {:def, _, [{^target_function, _, args}, [do: body]]} = node, nil ->
          if safe_length(args) == target_arity do
            {node, {:found, body}}
          else
            {node, nil}
          end

        {:defp, _, [{^target_function, _, args}, [do: body]]} = node, nil ->
          if safe_length(args) == target_arity do
            {node, {:found, body}}
          else
            {node, nil}
          end

        # Handle function with guards
        {:def, _, [{:when, _, [{^target_function, _, args} | _guards]}, [do: body]]} = node, nil ->
          if safe_length(args) == target_arity do
            {node, {:found, body}}
          else
            {node, nil}
          end

        {:defp, _, [{:when, _, [{^target_function, _, args} | _guards]}, [do: body]]} = node,
        nil ->
          if safe_length(args) == target_arity do
            {node, {:found, body}}
          else
            {node, nil}
          end

        node, acc ->
          {node, acc}
      end)

    case result do
      {_ast, {:found, body}} -> {:ok, body}
      {_ast, nil} -> :not_found
    end
  end

  # Helper to safely get length of args (which might be nil for 0-arity functions)
  defp safe_length(nil), do: 0
  defp safe_length(args) when is_list(args), do: length(args)
end
