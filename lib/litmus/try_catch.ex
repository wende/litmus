defmodule Litmus.TryCatch do
  @moduledoc """
  Try/catch block analysis for exception tracking.

  ## Current Status: PARTIALLY IMPLEMENTED

  This module implements try/catch handling by parsing Core Erlang AST to identify:
  1. Try/catch expressions in function bodies
  2. Catch patterns (which exception classes and types are caught)
  3. Exception subtraction from propagated exceptions

  ## Implementation Approach

  The module uses a two-phase approach:
  1. Extract Erlang abstract format from Elixir debug_info
  2. Compile to Core Erlang AST and walk it to find try/catch blocks

  ## Limitations

  If Core Erlang extraction fails (e.g., missing debug_info, unsupported format),
  the analysis falls back to CONSERVATIVE behavior:
  - Functions that catch exceptions will still report those exceptions as possible
  - The analysis over-reports exceptions but never under-reports
  - This is SAFE but not precise

  ## Example

      defmodule Example do
        def safe_hd(list) do
          try do
            hd(list)  # Raises ArgumentError
          catch
            :error, %ArgumentError{} -> :empty
          end
        end
      end

      # Current behavior:
      {:ok, results} = Litmus.analyze_exceptions(Example)
      Litmus.can_raise?(results, {Example, :safe_hd, 1}, ArgumentError)
      #=> true  (INCORRECT - ArgumentError is caught!)

      # Expected behavior (future):
      #=> false (ArgumentError is caught and doesn't propagate)

  ## Implementation Plan

  To implement try/catch handling:

  1. **Access Core Erlang AST**: Instead of using just `:purity_collect.file/1`,
     we need to parse the full Core Erlang AST using `:cerl` module.

  2. **Detect try/catch expressions**: Look for `{c_try, ...}` nodes in the AST.

  3. **Extract catch patterns**:
     ```erlang
     % In Core Erlang, try/catch looks like:
     {c_try, Body, Vars, BodyClause, CatchClauses, Handler}
     ```

  4. **Parse catch clauses** to determine which exceptions are caught:
     - `:error` class catches errors (ArgumentError, KeyError, etc.)
     - `:throw` class catches throws
     - `:exit` class catches exits
     - Patterns can match specific exception modules

  5. **Subtract caught exceptions**: Use `Litmus.Exceptions.subtract/2` to
     remove caught exceptions from the function's exception info.

  ## Example Implementation Sketch

      defp analyze_core_erlang(module) do
        {:ok, {^module, [{:abstract_code, {_, abstract_code}}]}} =
          :beam_lib.chunks(code_path, [:abstract_code])

        core_ast = :sys_core_fold.module(abstract_code, [])

        # Walk the Core Erlang AST
        :cerl_trees.fold(fn node, acc ->
          case :cerl.type(node) do
            :try ->
              # Extract catch patterns
              catch_clauses = :cerl.try_handler(node)
              caught = extract_caught_exceptions(catch_clauses)
              # Subtract from propagation
              # ...

            _ ->
              acc
          end
        end, initial_acc, core_ast)
      end

  ## References

  - Core Erlang documentation: https://www.erlang.org/doc/apps/compiler/cerl.html
  - `:cerl` module for AST manipulation
  - `:cerl_trees` for tree walking
  - PURITY source code for similar analysis patterns
  """

  @doc """
  Analyzes a BEAM file to extract try/catch information for all functions.

  Returns a map of MFA -> exception_info representing what exceptions are
  CAUGHT by each function (to be subtracted from what they raise).

  ## Parameters

    - `beam_path` - Path to the .beam file (string)

  ## Returns

    - `{:ok, %{mfa() => exception_info()}}` - Map of caught exceptions per function
    - `{:error, reason}` - If analysis fails
  """
  @spec analyze_beam(String.t()) :: {:ok, %{mfa() => Litmus.Exceptions.exception_info()}} | {:error, term()}
  def analyze_beam(beam_path) do
    charlist_path = String.to_charlist(beam_path)

    case :beam_lib.chunks(charlist_path, [:debug_info]) do
      {:ok, {module, [{:debug_info, debug_info}]}} ->
        case extract_core_erlang(debug_info) do
          {:ok, core_module} ->
            # Walk the Core Erlang AST to find try/catch in each function
            caught_map = analyze_core_module(module, core_module)
            {:ok, caught_map}

          {:error, reason} ->
            {:error, {:core_extraction_failed, reason}}
        end

      {:error, :beam_lib, reason} ->
        {:error, {:beam_lib_error, reason}}
    end
  end

  # Extract Core Erlang AST from debug_info chunk
  defp extract_core_erlang({:debug_info_v1, :elixir_erl, {:elixir_v1, elixir_data}}) do
    # For Elixir modules, first get Erlang AST, then compile to Core Erlang
    module = elixir_data.module

    try do
      # Get Erlang abstract format first
      case :elixir_erl.debug_info(:erlang_v1, module, elixir_data, %{}) do
        {:ok, {raw_abstract_v1, _}} ->
          # Compile Erlang AST to Core Erlang
          compile_abstract_to_core(raw_abstract_v1, module)

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, {:unexpected_erlang_v1_result, other}}
      end
    rescue
      error -> {:error, {:compilation_error, Exception.message(error)}}
    end
  end

  # Compile Erlang abstract format to Core Erlang
  defp compile_abstract_to_core(abstract_code, module) do
    try do
      # Use Erlang's compiler to convert abstract format to Core Erlang
      case :compile.forms(abstract_code, [:to_core, :return_errors, :return_warnings]) do
        {:ok, module_name, core_module, _warnings} when module_name == module ->
          {:ok, core_module}

        {:ok, _, core_module, _} ->
          # Module name mismatch, but still got core
          {:ok, core_module}

        {:error, errors, _warnings} ->
          {:error, {:compilation_errors, errors}}

        other ->
          {:error, {:unexpected_compile_result, other}}
      end
    rescue
      error -> {:error, {:core_compilation_error, Exception.message(error)}}
    end
  end

  defp extract_core_erlang({:debug_info_v1, backend, data}) do
    # For Erlang modules or other formats with older backend signature
    # Try with 4 args first (newer OTP), then fall back to 3 args
    try do
      case backend.debug_info(:core_erlang, :fake_module, data, %{}) do
        {:ok, core_module} -> {:ok, core_module}
        {:error, reason} -> {:error, reason}
      end
    rescue
      UndefinedFunctionError ->
        # Fall back to old 3-arg version (shouldn't happen in practice)
        {:error, :unsupported_backend_version}
    end
  end

  defp extract_core_erlang(other) do
    {:error, {:unsupported_debug_info_format, other}}
  end

  # Analyze a Core Erlang module to find try/catch in all functions
  defp analyze_core_module(module, core_module) do
    # Get all function definitions from the module
    functions = :cerl.module_defs(core_module)

    # Analyze each function
    Enum.reduce(functions, %{}, fn {name_var, body}, acc ->
      # Get function name and arity
      function_name = :cerl.fname_id(name_var)
      arity = :cerl.fname_arity(name_var)
      mfa = {module, function_name, arity}

      # Walk the function body to find try/catch
      caught = analyze_function_body(body)

      if Litmus.Exceptions.pure?(caught) do
        # No exceptions caught, don't add to map
        acc
      else
        Map.put(acc, mfa, caught)
      end
    end)
  end

  # Analyze a function body to find all try/catch expressions
  defp analyze_function_body(body) do
    # Walk the AST and collect all caught exceptions
    walk_ast(body, Litmus.Exceptions.empty())
  end

  # Walk the Core Erlang AST to find try expressions
  defp walk_ast(node, acc) do
    # First, check if this node is a try expression
    new_acc = case :cerl.type(node) do
      :try ->
        # Extract what this try/catch catches
        caught = extract_caught_from_try(node)
        Litmus.Exceptions.merge(acc, caught)

      _ ->
        acc
    end

    # Then recursively walk all children
    walk_children(node, new_acc)
  end

  # Walk all children of a Core Erlang node
  defp walk_children(node, acc) do
    case :cerl.type(node) do
      :var -> acc
      :literal -> acc

      :cons ->
        acc
        |> walk_ast(:cerl.cons_hd(node))
        |> walk_ast(:cerl.cons_tl(node))

      :tuple ->
        :cerl.tuple_es(node)
        |> Enum.reduce(acc, &walk_ast/2)

      :map ->
        pairs = :cerl.map_es(node)
        Enum.reduce(pairs, acc, fn pair, a ->
          a
          |> walk_ast(:cerl.map_pair_key(pair))
          |> walk_ast(:cerl.map_pair_val(pair))
        end)

      :values ->
        :cerl.values_es(node)
        |> Enum.reduce(acc, &walk_ast/2)

      :apply ->
        op = :cerl.apply_op(node)
        args = :cerl.apply_args(node)
        Enum.reduce([op | args], acc, &walk_ast/2)

      :call ->
        module = :cerl.call_module(node)
        name = :cerl.call_name(node)
        args = :cerl.call_args(node)
        Enum.reduce([module, name | args], acc, &walk_ast/2)

      :primop ->
        args = :cerl.primop_args(node)
        Enum.reduce(args, acc, &walk_ast/2)

      :case ->
        arg = :cerl.case_arg(node)
        clauses = :cerl.case_clauses(node)
        acc = walk_ast(arg, acc)
        Enum.reduce(clauses, acc, &walk_clause/2)

      :clause ->
        walk_clause(node, acc)

      :let ->
        arg = :cerl.let_arg(node)
        body = :cerl.let_body(node)
        acc
        |> walk_ast(arg)
        |> walk_ast(body)

      :letrec ->
        defs = :cerl.letrec_defs(node)
        body = :cerl.letrec_body(node)
        acc = Enum.reduce(defs, acc, fn {_var, fun}, a -> walk_ast(fun, a) end)
        walk_ast(body, acc)

      :fun ->
        body = :cerl.fun_body(node)
        walk_ast(body, acc)

      :seq ->
        arg = :cerl.seq_arg(node)
        body = :cerl.seq_body(node)
        acc
        |> walk_ast(arg)
        |> walk_ast(body)

      :try ->
        arg = :cerl.try_arg(node)
        body = :cerl.try_body(node)
        handler = :cerl.try_handler(node)
        acc
        |> walk_ast(arg)
        |> walk_ast(body)
        |> walk_ast(handler)

      :catch ->
        body = :cerl.catch_body(node)
        walk_ast(body, acc)

      :receive ->
        clauses = :cerl.receive_clauses(node)
        timeout = :cerl.receive_timeout(node)
        action = :cerl.receive_action(node)
        acc = Enum.reduce(clauses, acc, &walk_clause/2)
        acc
        |> walk_ast(timeout)
        |> walk_ast(action)

      :binary ->
        segments = :cerl.binary_segments(node)
        Enum.reduce(segments, acc, fn seg, a ->
          val = :cerl.bitstr_val(seg)
          size = :cerl.bitstr_size(seg)
          a
          |> walk_ast(val)
          |> walk_ast(size)
        end)

      # Unknown or unsupported node types
      _ ->
        acc
    end
  end

  # Walk a clause node
  defp walk_clause(clause, acc) do
    guard = :cerl.clause_guard(clause)
    body = :cerl.clause_body(clause)
    acc
    |> walk_ast(guard)
    |> walk_ast(body)
  end

  # Extract caught exceptions from a try expression
  defp extract_caught_from_try(try_node) do
    # Get the handler (exception variables not needed for pattern extraction)
    handler = :cerl.try_handler(try_node)

    # Handler is typically a case expression over the exception variables
    case :cerl.type(handler) do
      :case ->
        # Get the clauses
        clauses = :cerl.case_clauses(handler)
        extract_caught_from_clauses(clauses)

      _ ->
        # Handler is not a case - this is unusual
        # Conservative: assume nothing is caught
        Litmus.Exceptions.empty()
    end
  end

  # Extract caught exceptions from catch clauses
  defp extract_caught_from_clauses(clauses) when is_list(clauses) do
    Enum.reduce(clauses, Litmus.Exceptions.empty(), fn clause, acc ->
      caught = extract_caught_from_clause(clause)
      Litmus.Exceptions.merge(acc, caught)
    end)
  end

  # Extract caught exceptions from a single catch clause
  defp extract_caught_from_clause(clause) do
    # Get the pattern - it's a tuple of {Class, Exception, Stacktrace}
    patterns = :cerl.clause_pats(clause)

    case patterns do
      [pattern] ->
        # Pattern is a tuple {Class, Exception, Stack}
        case :cerl.type(pattern) do
          :tuple ->
            elements = :cerl.tuple_es(pattern)

            case elements do
              [class_pat, exception_pat | _] ->
                extract_caught_from_pattern(class_pat, exception_pat)

              _ ->
                Litmus.Exceptions.empty()
            end

          _ ->
            Litmus.Exceptions.empty()
        end

      _ ->
        Litmus.Exceptions.empty()
    end
  end

  # Extract caught exceptions from class and exception patterns
  defp extract_caught_from_pattern(class_pat, exception_pat) do
    # Determine the exception class
    class = extract_exception_class(class_pat)

    case class do
      :error ->
        # Catches typed exceptions - determine which ones
        extract_error_exceptions(exception_pat)

      :throw ->
        # Catches throw
        Litmus.Exceptions.non_error()

      :exit ->
        # Catches exit
        Litmus.Exceptions.non_error()

      :all ->
        # Catches everything (pattern is a variable)
        Litmus.Exceptions.error_dynamic()
        |> Litmus.Exceptions.merge(Litmus.Exceptions.non_error())

      :unknown ->
        # Can't determine - conservative
        Litmus.Exceptions.empty()
    end
  end

  # Extract the exception class from a pattern
  defp extract_exception_class(class_pat) do
    case :cerl.type(class_pat) do
      :literal ->
        # Literal atom like :error, :throw, :exit
        case :cerl.concrete(class_pat) do
          :error -> :error
          :throw -> :throw
          :exit -> :exit
          _ -> :unknown
        end

      :var ->
        # Variable - catches all classes
        :all

      _ ->
        :unknown
    end
  end

  # Extract which error exceptions are caught
  defp extract_error_exceptions(exception_pat) do
    case :cerl.type(exception_pat) do
      :var ->
        # Variable - catches all errors
        Litmus.Exceptions.error_dynamic()

      :map ->
        # Struct pattern like %ArgumentError{} is represented as a map in Core Erlang
        # Look for the __struct__ key
        pairs = :cerl.map_es(exception_pat)

        # Find the __struct__ key
        struct_module = Enum.find_value(pairs, fn pair ->
          key = :cerl.map_pair_key(pair)
          val = :cerl.map_pair_val(pair)

          if :cerl.type(key) == :literal and :cerl.concrete(key) == :__struct__ do
            if :cerl.type(val) == :literal do
              :cerl.concrete(val)
            end
          end
        end)

        case struct_module do
          nil ->
            # No __struct__ key or not a literal
            Litmus.Exceptions.error_dynamic()

          module when is_atom(module) ->
            if exception_module?(module) do
              Litmus.Exceptions.error(module)
            else
              Litmus.Exceptions.error_dynamic()
            end
        end

      :tuple ->
        # Old-style struct representation (shouldn't happen in modern Elixir)
        # But keep for compatibility
        elements = :cerl.tuple_es(exception_pat)

        case elements do
          [struct_key, module_lit | _] ->
            # Check if first element is :__struct__
            if :cerl.type(struct_key) == :literal and
                 :cerl.concrete(struct_key) == :__struct__ and
                 :cerl.type(module_lit) == :literal do
              # Extract the exception module
              module = :cerl.concrete(module_lit)

              if is_atom(module) and exception_module?(module) do
                Litmus.Exceptions.error(module)
              else
                Litmus.Exceptions.error_dynamic()
              end
            else
              Litmus.Exceptions.error_dynamic()
            end

          _ ->
            Litmus.Exceptions.error_dynamic()
        end

      _ ->
        # Other patterns - conservative
        Litmus.Exceptions.error_dynamic()
    end
  end

  # Check if a module is an exception module
  defp exception_module?(module) do
    # Common exception modules
    module in [
      ArgumentError,
      ArithmeticError,
      BadArityError,
      BadBooleanError,
      BadFunctionError,
      BadMapError,
      BadStructError,
      CaseClauseError,
      CondClauseError,
      ErlangError,
      FunctionClauseError,
      KeyError,
      MatchError,
      Protocol.UndefinedError,
      RuntimeError,
      SystemLimitError,
      UndefinedFunctionError,
      WithClauseError
    ] or String.ends_with?(Atom.to_string(module), "Error")
  end
end
