defmodule Litmus.Effects do
  @moduledoc """
  Algebraic effects system for Elixir using continuation-passing style (CPS).

  This module provides a way to extract side effects from code, allowing you to:
  - Test effectful code with mock implementations
  - Replay effects deterministically
  - Compose and transform effects

  ## Basic Usage

      effect do
        content = File.read!("config.json")
        parsed = Jason.decode!(content)
        File.write!("output.txt", parsed["result"])
      end
      |> Effects.run(fn
        {File, :read!, ["config.json"]} ->
          ~s({"result": "test data"})
        {File, :write!, ["output.txt", data]} ->
          :ok
      end)

  ## How It Works

  The `effect/1` macro transforms your code using continuation-passing style (CPS).
  Each side effect becomes a "pause point" where control is yielded to a handler.
  Pure code between effects runs normally without transformation.

  ## Example

      # Original code
      effect do
        x = File.read!("a.txt")
        y = String.upcase(x)  # Pure - runs normally
        File.write!("b.txt", y)
      end

      # Conceptually transforms to:
      fn handler ->
        handler.({File, :read!, ["a.txt"]}, fn x ->
          y = String.upcase(x)  # Not transformed
          handler.({File, :write!, ["b.txt", y]}, fn _result ->
            :ok
          end)
        end)
      end

  """

  alias Litmus.Effects.Transformer

  @doc """
  Creates an effect block with inline effect handlers.

  ## Syntax

      effect do
        # Your code with effects
        x = File.read!("config.json")
        IO.puts("Loaded: \#{x}")
      catch
        {File, :read!, ["config.json"]} -> "mocked content"
        {IO, :puts, [msg]} -> :ok
      end

  ## Options

  You can also pass options before the do/catch block:

      effect track: [:file] do
        File.read!("test.txt")
      catch
        {File, :read!, _} -> "mocked"
      end

  ## Examples

      # Basic usage
      result = effect do
        File.read!("test.txt")
      catch
        {File, :read!, _} -> "test content"
      end

      # With branching
      result = effect do
        x = if flag do
          File.read!("a.txt")
        else
          "default"
        end
        File.write!("b.txt", x)
      catch
        {File, :read!, _} -> "mocked"
        {File, :write!, _} -> :ok
      end

      # With external handler function
      mock_handler = fn
        {File, :read!, _} -> "mocked"
      end

      result = effect do
        File.read!("test.txt")
      catch: mock_handler
  """
  defmacro effect(opts_or_block)

  # effect/1 clauses - single argument forms

  # effect do ... catch ... rescue ... end
  defmacro effect(do: code_block, catch: catch_clauses, rescue: rescue_clauses)
           when is_list(catch_clauses) and is_list(rescue_clauses) do
    build_effect_with_handler_and_rescue(
      code_block,
      catch_clauses,
      rescue_clauses,
      [],
      __CALLER__
    )
  end

  # effect do ... catch ... end
  defmacro effect(do: code_block, catch: catch_clauses) when is_list(catch_clauses) do
    build_effect_with_handler(code_block, catch_clauses, [], __CALLER__)
  end

  # effect do ... catch: handler_fn
  defmacro effect(do: code_block, catch: handler_fn) do
    build_effect_with_external_handler(code_block, handler_fn, [], __CALLER__)
  end

  # Legacy support: effect do ... end (returns function)
  defmacro effect(do: block) do
    build_effect_function(block, [], __CALLER__)
  end

  # effect/2 clauses - two argument forms with options

  # effect track: [:file] do ... catch ... rescue ... end
  defmacro effect(opts, do: code_block, catch: catch_clauses, rescue: rescue_clauses)
           when is_list(catch_clauses) and is_list(rescue_clauses) do
    build_effect_with_handler_and_rescue(
      code_block,
      catch_clauses,
      rescue_clauses,
      opts,
      __CALLER__
    )
  end

  # effect track: [:file] do ... catch ... end
  defmacro effect(opts, do: code_block, catch: catch_clauses) when is_list(catch_clauses) do
    build_effect_with_handler(code_block, catch_clauses, opts, __CALLER__)
  end

  # effect track: [:file] do ... catch: handler_fn
  defmacro effect(opts, do: code_block, catch: handler_fn) do
    build_effect_with_external_handler(code_block, handler_fn, opts, __CALLER__)
  end

  # Legacy support: effect track: [:file] do ... end (returns function)
  defmacro effect(opts, do: block) when is_list(opts) do
    build_effect_function(block, opts, __CALLER__)
  end

  # Build effect with inline catch clauses
  defp build_effect_with_handler(code_block, catch_clauses, opts, caller) do
    opts = Keyword.validate!(opts, track: :all, passthrough: false)

    # Expand all macros in the code block FIRST
    expanded_block = expand_all_macros(code_block, caller)

    # Transform the code block to CPS
    transformed = Transformer.transform_block(expanded_block, opts)

    # Generate handler function from catch clauses that handles continuations
    handler_fn =
      quote do
        fn effect_sig, cont ->
          result =
            try do
              case effect_sig do
                unquote(catch_clauses)
              end
            rescue
              e in CaseClauseError ->
                reraise Litmus.Effects.UnhandledError.exception(effect_sig), __STACKTRACE__
            end

          cont.(result)
        end
      end

    # Replace __handler__ with the generated handler
    final_ast =
      Macro.postwalk(transformed, fn
        {:__handler__, _, nil} -> handler_fn
        other -> other
      end)

    # Execute immediately
    quote do
      (fn -> unquote(final_ast) end).()
    end
  end

  # Build effect with inline catch clauses AND rescue clauses
  defp build_effect_with_handler_and_rescue(
         code_block,
         catch_clauses,
         rescue_clauses,
         opts,
         caller
       ) do
    opts = Keyword.validate!(opts, track: :all, passthrough: false)

    # Expand all macros in the code block FIRST
    expanded_block = expand_all_macros(code_block, caller)

    # Transform the code block to CPS
    transformed = Transformer.transform_block(expanded_block, opts)

    # Generate handler function from catch clauses that handles continuations AND exceptions
    handler_fn =
      quote do
        fn effect_sig, cont ->
          result =
            try do
              case effect_sig do
                unquote(catch_clauses)
              end
            rescue
              e in CaseClauseError ->
                reraise Litmus.Effects.UnhandledError.exception(effect_sig), __STACKTRACE__
            end

          cont.(result)
        end
      end

    # Replace __handler__ with the generated handler
    final_ast =
      Macro.postwalk(transformed, fn
        {:__handler__, _, nil} -> handler_fn
        other -> other
      end)

    # Wrap the entire effect execution in try/rescue with user's rescue clauses
    quote do
      try do
        (fn -> unquote(final_ast) end).()
      rescue
        unquote(rescue_clauses)
      end
    end
  end

  # Build effect with external handler function
  defp build_effect_with_external_handler(code_block, handler_fn, opts, caller) do
    opts = Keyword.validate!(opts, track: :all, passthrough: false)

    # Expand all macros in the code block FIRST
    expanded_block = expand_all_macros(code_block, caller)

    # Transform the code block to CPS
    transformed = Transformer.transform_block(expanded_block, opts)

    # Wrap the user's handler to handle continuations
    # User handlers take 1 arg (effect sig), we need to wrap them to take 2 args (effect sig, cont)
    wrapped_handler =
      quote do
        fn effect_sig, cont ->
          result =
            try do
              unquote(handler_fn).(effect_sig)
            rescue
              e in FunctionClauseError ->
                reraise Litmus.Effects.UnhandledError.exception(effect_sig), __STACKTRACE__
            end

          cont.(result)
        end
      end

    # Replace __handler__ with the wrapped handler
    final_ast =
      Macro.postwalk(transformed, fn
        {:__handler__, _, nil} -> wrapped_handler
        other -> other
      end)

    # Execute immediately
    quote do
      (fn -> unquote(final_ast) end).()
    end
  end

  # Build effect function (legacy API)
  defp build_effect_function(block, opts, caller) do
    opts = Keyword.validate!(opts, track: :all, passthrough: false)

    # Expand all macros in the code block FIRST
    expanded_block = expand_all_macros(block, caller)

    # Transform the block to CPS at compile time
    transformed = Transformer.transform_block(expanded_block, opts)

    # Replace __handler__ variable with the actual parameter
    handler_var = quote do: var!(___handler___, Litmus.Effects)

    final_ast =
      Macro.postwalk(transformed, fn
        {:__handler__, _, nil} -> handler_var
        other -> other
      end)

    # Wrap in a function that takes the handler
    quote do
      fn var!(___handler___, Litmus.Effects) ->
        unquote(final_ast)
      end
    end
  end

  @doc """
  Runs an effect block with the given handler.

  The handler is a function that receives effect signatures and returns results:

      handler.({Module, :function, [args]}) -> result

  Special handler values:
  - `:passthrough` - Execute all effects normally
  - `:mock` - Raise an error for any unhandled effect

  ## Examples

      # Custom handler
      effect do
        File.read!("test.txt")
      end
      |> Effects.run(fn
        {File, :read!, [_]} -> "mocked content"
      end)

      # Passthrough (normal execution)
      effect do
        File.read!("test.txt")
      end
      |> Effects.run(:passthrough)
  """
  @spec run((any() -> any()), :passthrough | (any() -> any())) :: any()
  def run(effect_fn, handler) when is_function(effect_fn, 1) do
    # Create the actual handler function that will be passed to the effect
    handler_fn =
      case handler do
        :passthrough ->
          fn effect_sig, cont ->
            result = apply_effect(effect_sig)
            cont.(result)
          end

        handler when is_function(handler, 1) ->
          fn effect_sig, cont ->
            result = handler.(effect_sig)
            cont.(result)
          end
      end

    # Call the effect function with our handler
    effect_fn.(handler_fn)
  end

  @doc """
  Applies an effect signature directly (for passthrough mode).
  """
  @spec apply_effect({module(), atom(), [any()]}) :: any()
  def apply_effect({module, function, args}) do
    apply(module, function, args)
  end

  @doc """
  Maps over effects, allowing transformation or replacement.

  ## Examples

      effect do
        File.read!("data.txt")
      end
      |> Effects.map(fn
        {File, :read!, [path]} ->
          {File, :read!, ["/mock/" <> path]}
      end)
      |> Effects.run(:passthrough)
  """
  @spec map((any() -> any()), (any() -> any())) :: (any() -> any())
  def map(effect_fn, mapper) when is_function(effect_fn, 1) and is_function(mapper, 1) do
    fn handler ->
      effect_fn.(fn effect_sig, cont ->
        new_effect = mapper.(effect_sig)
        handler.(new_effect, cont)
      end)
    end
  end

  @doc """
  Composes two effect handlers, trying the first and falling back to the second.

  ## Examples

      file_handler = fn
        {File, _, _} = eff -> handle_file(eff)
      end

      io_handler = fn
        {IO, _, _} = eff -> handle_io(eff)
      end

      combined = Effects.compose(file_handler, io_handler)
  """
  @spec compose((any() -> any()), (any() -> any())) :: (any() -> any())
  def compose(handler1, handler2) do
    fn effect_sig ->
      try do
        handler1.(effect_sig)
      rescue
        FunctionClauseError -> handler2.(effect_sig)
      end
    end
  end

  # Expand all macros in an AST using the caller's environment
  defp expand_all_macros(ast, caller) do
    Macro.prewalk(ast, fn node ->
      Macro.expand(node, caller)
    end)
  end
end
