defmodule Litmus.Stdlib do
  @moduledoc """
  Whitelist-based purity classifications for Elixir standard library.

  This module provides a curated whitelist of pure functions from the Elixir
  standard library. For maximum safety, only explicitly whitelisted functions
  are considered pure - everything else is assumed to have side effects.

  ## Whitelist Format

  The whitelist supports three formats:

  1. **Entire module**: All functions in the module are pure
     ```
     Module => :all
     ```

  2. **Module with exceptions**: All functions except specified ones are pure
     ```
     Module => {:all_except, [{:function_name, arity}, ...]}
     ```

  3. **Specific functions**: Only listed functions/arities are pure
     ```
     Module => %{function_name: [arity1, arity2, ...]}
     ```

  ## Example

      # Check if a function is whitelisted
      Litmus.Stdlib.whitelisted?({Enum, :map, 2})
      #=> true

      Litmus.Stdlib.whitelisted?({IO, :puts, 1})
      #=> false

      # Get all whitelisted functions for a module
      Litmus.Stdlib.get_module_whitelist(Enum)
      #=> :all

  ## Philosophy

  This is a **whitelist**, not a blacklist. Only functions explicitly marked
  as pure are considered safe for optimization. Unknown functions default to
  impure for maximum safety.

  Most Elixir stdlib functions work with immutable data structures and are pure,
  but some notable exceptions include:
  - `String.to_atom/1`, `String.to_existing_atom/1` (atom table mutation)
  - Any function that performs I/O
  - Any function that uses randomness
  - Any function that depends on system state
  """

  @type purity_level :: :pure | :exceptions | :dependent | :nif | :side_effects
  @type termination_level :: :terminating | :non_terminating

  @type whitelist_rule ::
          :all
          | {:all_except, [{atom(), arity()}]}
          | %{atom() => [arity()]}
          | {:all, purity_level()}
          | {:all_except, [{atom(), arity()}], purity_level()}
          | %{atom() => [{arity(), purity_level()}]}

  @doc """
  The whitelist of pure functions in Elixir's standard library.

  This is the source of truth for which Elixir stdlib functions are
  considered pure for static analysis purposes.
  """
  @spec whitelist() :: %{module() => whitelist_rule()}
  def whitelist do
    %{
      # Core data structure modules - mostly pure
      Enum => {:all_except, []},
      List => :all,
      Tuple => :all,
      Map => {:all_except, []},
      MapSet => :all,
      Keyword => :all,
      Range => :all,
      Stream => {:all_except, []},

      # String module - mostly pure except atom conversions
      String => {
        :all_except,
        [
          # These mutate the atom table - side effects!
          {:to_atom, 1},
          {:to_existing_atom, 1}
        ]
      },

      # Math and numeric operations
      # Most functions are pure, but parsing can raise exceptions
      Integer => %{
        :digits => [1, 2],
        :floor_div => [2],
        :gcd => [2],
        :mod => [2],
        :pow => [2],
        :undigits => [1, 2],
        :to_charlist => [1, 2],
        :to_string => [1, 2],
        # These can raise on invalid input
        :parse => [{1, :exceptions}, {2, :exceptions}],
        :to_charlist! => [{1, :exceptions}],
        :to_string! => [{1, :exceptions}]
      },
      Float => :all,

      # Date/Time modules - pure (immutable data structures)
      Date => :all,
      Time => :all,
      DateTime => {:all_except, [{:now, 2}, {:utc_now, 0}, {:utc_now, 1}, {:utc_now, 2}]},
      NaiveDateTime => {:all_except, [{:local_now, 0}, {:utc_now, 0}, {:utc_now, 1}]},

      # Code manipulation - pure (AST operations)
      Macro => {:all_except, [{:escape, 2}]},

      # Version - pure
      Version => :all,

      # Regex - depends on compilation but results are deterministic
      Regex => {:all_except, [{:compile, 1}, {:compile, 2}, {:recompile, 1}, {:recompile, 2}]},

      # URI - pure data structure operations
      URI => :all,

      # Path - pure string operations (doesn't touch filesystem)
      Path => :all,

      # Exception - pure (creates data structures)
      Exception => :all,

      # Kernel - selective whitelist (many functions have side effects)
      Kernel => %{
        # Arithmetic
        :+ => [1, 2],
        :- => [1, 2],
        :* => [2],
        :/ => [2],
        :div => [2],
        :rem => [2],
        :abs => [1],
        :ceil => [1],
        :floor => [1],
        :round => [1],
        :trunc => [1],

        # Comparison
        :== => [2],
        :!= => [2],
        :=== => [2],
        :!== => [2],
        :< => [2],
        :> => [2],
        :<= => [2],
        :>= => [2],

        # Boolean
        :! => [1],
        :and => [2],
        :or => [2],
        :not => [1],

        # Special forms and operators (pure language constructs)
        :|> => [2],
        :. => [2],
        :-> => [2],
        :fn => [1, 2, 3],
        :__aliases__ => [1, 2, 3],
        := => [2],
        :__block__ => [1, 2, 3, 4, 5],
        :& => [1],
        :case => [2],
        :cond => [1],
        :if => [2, 3],
        :unless => [2, 3],
        :for => [1, 2],
        :with => [1, 2],
        :receive => [1],
        :try => [1],
        :quote => [1, 2],
        :unquote => [1],
        :"%{}" => [0, 1, 2, 3, 4, 5],  # Map literal syntax
        :"{}" => [0, 1, 2, 3, 4, 5],  # Tuple literal syntax
        :"[]" => [0, 1, 2, 3, 4, 5],  # List literal syntax
        :"<<>>" => [0, 1, 2, 3, 4, 5],  # Binary literal syntax

        # Bitwise
        :&&& => [2],
        :<<< => [2],
        :>>> => [2],
        :^^^ => [2],
        :~~~ => [1],
        :|||  => [2],

        # Data structure operations
        :++ => [2],
        :-- => [2],
        :hd => [1],
        :tl => [1],
        :length => [1],
        :elem => [2],
        :put_elem => [3],
        :get_in => [2],
        :put_in => [3],
        :update_in => [3],
        :pop_in => [2],

        # Type checks
        :is_atom => [1],
        :is_binary => [1],
        :is_bitstring => [1],
        :is_boolean => [1],
        :is_float => [1],
        :is_function => [1, 2],
        :is_integer => [1],
        :is_list => [1],
        :is_map => [1],
        :is_map_key => [2],
        :is_nil => [1],
        :is_number => [1],
        :is_pid => [1],
        :is_port => [1],
        :is_reference => [1],
        :is_tuple => [1],
        :is_exception => [1, 2],

        # Conversions
        :to_string => [1],
        :to_charlist => [1],

        # Utilities
        :max => [2],
        :min => [2],
        :byte_size => [1],
        :bit_size => [1],
        :tuple_size => [1],
        :map_size => [1]

        # Explicitly NOT whitelisted:
        # - :apply/2, :apply/3 - dynamic dispatch
        # - :send/2 - process message passing
        # - :spawn/* - process creation
        # - :raise/* - exceptions
        # - :throw/1, :exit/1 - control flow
        # - :inspect/2 - depends on protocols
        # - :node/0, :node/1 - system dependent
        # - :make_ref/0 - generates unique references
        # - :self/0 - process dependent
        # - System.* - all have side effects or system dependencies
        # - IO.* - all have I/O side effects
        # - File.* - all have I/O side effects
        # - Process.* - all have process side effects
        # - Port.* - all have I/O side effects
        # - :atomics/* - mutable state
        # - :ets/* - mutable state
        # - :persistent_term/* - global state
      }

      # Explicitly NOT whitelisted modules:
      # - IO - all I/O operations
      # - File - all filesystem operations
      # - System - system calls, environment variables
      # - Process - process operations
      # - Port - I/O ports
      # - Agent - stateful processes
      # - Task - concurrent execution
      # - GenServer - stateful processes
      # - Registry - stateful registry
      # - Application - application state
      # - Code - code loading/compilation
      # - Node - distributed operations
    }
  end

  @doc """
  Gets the purity level of a whitelisted function.

  Returns the purity level if the function is whitelisted, or `nil` otherwise.

  ## Examples

      iex> Litmus.Stdlib.get_purity_level({Enum, :map, 2})
      :pure

      iex> Litmus.Stdlib.get_purity_level({String, :to_integer, 1})
      :exceptions

      iex> Litmus.Stdlib.get_purity_level({IO, :puts, 1})
      nil
  """
  @spec get_purity_level(mfa()) :: purity_level() | nil
  def get_purity_level({module, function, arity}) when is_atom(module) and is_atom(function) and is_integer(arity) do
    case Map.get(whitelist(), module) do
      nil ->
        nil

      :all ->
        :pure

      {:all, level} ->
        level

      {:all_except, exceptions} ->
        if {function, arity} in exceptions do
          nil
        else
          :pure
        end

      {:all_except, exceptions, level} ->
        if {function, arity} in exceptions do
          nil
        else
          level
        end

      function_map when is_map(function_map) ->
        case Map.get(function_map, function) do
          nil ->
            nil

          arity_list when is_list(arity_list) ->
            # Handle both plain arities and {arity, level} tuples
            Enum.find_value(arity_list, fn
              {^arity, level} -> level
              ^arity -> :pure
              _ -> nil
            end)
        end
    end
  end

  # Fallback for invalid MFA tuples
  def get_purity_level(_), do: nil

  @doc """
  Checks if a function is whitelisted as pure.

  Returns `true` if the function is explicitly whitelisted, `false` otherwise.

  ## Examples

      iex> Litmus.Stdlib.whitelisted?({Enum, :map, 2})
      true

      iex> Litmus.Stdlib.whitelisted?({String, :to_atom, 1})
      false

      iex> Litmus.Stdlib.whitelisted?({IO, :puts, 1})
      false

      iex> Litmus.Stdlib.whitelisted?({Integer, :to_string, 1})
      true
  """
  @spec whitelisted?(mfa()) :: boolean()
  def whitelisted?(mfa) do
    get_purity_level(mfa) != nil
  end

  @doc """
  Checks if a function meets a specific purity level requirement.

  Returns `true` if the function is whitelisted and its purity level
  is at least as pure as the required level.

  ## Purity Hierarchy (from strictest to most permissive)

  - `:pure` - Only pure functions allowed
  - `:exceptions` - Pure and exception-raising functions allowed
  - `:dependent` - Pure, exceptions, and environment-dependent allowed
  - `:nif` - Pure, exceptions, dependent, and NIF functions allowed (native code, behavior unknown)
  - `:side_effects` - Everything including I/O and state mutation allowed

  NIFs represent a distinct purity level between `:dependent` and `:side_effects` because
  they call native code that cannot be statically analyzed, but may not necessarily perform I/O.

  ## Examples

      iex> Litmus.Stdlib.meets_level?({Enum, :map, 2}, :pure)
      true

      iex> Litmus.Stdlib.meets_level?({String, :to_integer, 1}, :pure)
      false

      iex> Litmus.Stdlib.meets_level?({String, :to_integer, 1}, :exceptions)
      true

      iex> Litmus.Stdlib.meets_level?({IO, :puts, 1}, :side_effects)
      false
  """
  @spec meets_level?(mfa(), purity_level()) :: boolean()
  def meets_level?(mfa, required_level) do
    case get_purity_level(mfa) do
      nil -> false
      actual_level -> level_acceptable?(actual_level, required_level)
    end
  end

  # Check if actual level meets the required level
  defp level_acceptable?(actual, required) do
    level_order = [:pure, :exceptions, :dependent, :nif, :side_effects]
    actual_idx = Enum.find_index(level_order, &(&1 == actual))
    required_idx = Enum.find_index(level_order, &(&1 == required))

    actual_idx != nil and required_idx != nil and actual_idx <= required_idx
  end

  @doc """
  Gets the whitelist rule for a specific module.

  Returns the whitelist rule if the module is whitelisted, or `nil` otherwise.

  ## Examples

      iex> Litmus.Stdlib.get_module_whitelist(Enum)
      {:all_except, []}

      iex> Litmus.Stdlib.get_module_whitelist(List)
      :all

      iex> Litmus.Stdlib.get_module_whitelist(IO)
      nil
  """
  @spec get_module_whitelist(module()) :: whitelist_rule() | nil
  def get_module_whitelist(module) when is_atom(module) do
    Map.get(whitelist(), module)
  end

  @doc """
  Lists all whitelisted modules.

  Returns a list of all modules that have at least some whitelisted functions.

  ## Examples

      iex> modules = Litmus.Stdlib.whitelisted_modules()
      iex> Enum in modules
      true
      iex> IO in modules
      false
  """
  @spec whitelisted_modules() :: [module()]
  def whitelisted_modules do
    Map.keys(whitelist())
  end

  @doc """
  Counts how many functions are whitelisted for a module.

  Note: For `:all` and `{:all_except, _}` rules, this requires analyzing
  the actual module to count functions, so it returns `:many` as a placeholder.

  ## Examples

      iex> Litmus.Stdlib.count_whitelisted(List)
      :many

      iex> Litmus.Stdlib.count_whitelisted(Kernel) |> is_integer()
      true
  """
  @spec count_whitelisted(module()) :: :many | non_neg_integer()
  def count_whitelisted(module) when is_atom(module) do
    case get_module_whitelist(module) do
      nil ->
        0

      :all ->
        :many

      {:all_except, _} ->
        :many

      function_map when is_map(function_map) ->
        function_map
        |> Map.values()
        |> Enum.map(&length/1)
        |> Enum.sum()
    end
  end

  @doc """
  Expands a whitelist rule into a list of specific MFA tuples.

  For `:all` and `{:all_except, _}` rules, this analyzes the module
  to enumerate all functions.

  ## Examples

      iex> Litmus.Stdlib.expand_rule(Integer, :all)
      [{Integer, :digits, 1}, {Integer, :digits, 2}, ...]
  """
  @spec expand_rule(module(), whitelist_rule()) :: [mfa()]
  def expand_rule(module, rule) do
    case rule do
      :all ->
        get_all_module_functions(module)

      {:all_except, exceptions} ->
        all_funcs = get_all_module_functions(module)
        exception_set = MapSet.new(exceptions)

        Enum.filter(all_funcs, fn {^module, func, arity} ->
          {func, arity} not in exception_set
        end)

      function_map when is_map(function_map) ->
        for {func, arities} <- function_map,
            arity <- arities do
          {module, func, arity}
        end
    end
  end

  # Private helper to get all exported functions from a module
  defp get_all_module_functions(module) do
    if Code.ensure_loaded?(module) do
      module.__info__(:functions)
      |> Enum.map(fn {func, arity} -> {module, func, arity} end)
    else
      []
    end
  end

  @doc """
  Whitelist of non-terminating functions in Elixir's standard library.

  Most Elixir stdlib functions terminate. This list explicitly marks
  the functions that may run forever (infinite loops, blocking I/O, etc.).

  ## Non-terminating Categories

  1. **Stream operations** - Lazy evaluation, potentially infinite
  2. **Process operations** - Blocking calls, infinite waits
  3. **Infinite generators** - Functions that produce infinite sequences

  ## Philosophy

  Conservative approach: Only mark functions as non-terminating when we're
  certain they may not terminate. Everything else is assumed to terminate.
  """
  @spec termination_blacklist() :: %{module() => [{atom(), arity()}]}
  def termination_blacklist do
    %{
      # Stream module - lazy operations, potentially infinite
      Stream => [
        # Infinite generators
        {:cycle, 1},
        {:iterate, 2},
        {:repeatedly, 1},
        {:resource, 3},
        {:unfold, 2}
        # Note: Most Stream operations are lazy but terminate when consumed
      ],

      # Process operations - may block indefinitely
      Process => [
        {:sleep, 1},
        {:hibernate, 3}
      ],

      # GenServer - blocking calls
      GenServer => [
        {:call, 2},
        {:call, 3}
        # May timeout but could block indefinitely
      ],

      # Task - waiting operations
      Task => [
        {:await, 1},
        {:await, 2},
        {:await_many, 1},
        {:await_many, 2}
      ],

      # Agent - blocking operations
      Agent => [
        {:get, 2},
        {:get, 3},
        {:get_and_update, 2},
        {:get_and_update, 3},
        {:update, 2},
        {:update, 3}
      ]

      # Note: Kernel receive expressions are handled by PURITY
      # Note: IO operations are already excluded from purity whitelist
    }
  end

  @doc """
  Checks if a function is guaranteed to terminate.

  Returns `true` if the function is NOT in the termination blacklist,
  meaning it's expected to terminate. Non-terminating functions return `false`.

  ## Examples

      iex> Litmus.Stdlib.terminates?({Enum, :map, 2})
      true

      iex> Litmus.Stdlib.terminates?({Stream, :cycle, 1})
      false

      iex> Litmus.Stdlib.terminates?({Process, :sleep, 1})
      false
  """
  @spec terminates?(mfa()) :: boolean()
  def terminates?({module, function, arity}) when is_atom(module) and is_atom(function) and is_integer(arity) do
    case Map.get(termination_blacklist(), module) do
      nil ->
        # Module not in blacklist - assume terminates
        true

      blacklist_functions ->
        # Check if specific function is blacklisted
        {function, arity} not in blacklist_functions
    end
  end

  # Fallback for invalid MFA tuples
  def terminates?(_), do: true

  @doc """
  Gets the termination status of a function.

  Returns the termination level with optional reason.

  ## Examples

      iex> Litmus.Stdlib.get_termination({Enum, :map, 2})
      :terminating

      iex> Litmus.Stdlib.get_termination({Stream, :cycle, 1})
      :non_terminating

      iex> Litmus.Stdlib.get_termination({Process, :sleep, 1})
      :non_terminating
  """
  @spec get_termination(mfa()) :: termination_level()
  def get_termination(mfa) do
    if terminates?(mfa) do
      :terminating
    else
      :non_terminating
    end
  end

  @doc """
  Lists all modules that have non-terminating functions.

  Returns a list of modules with at least one non-terminating function.

  ## Examples

      iex> modules = Litmus.Stdlib.non_terminating_modules()
      iex> Stream in modules
      true
      iex> Process in modules
      true
      iex> Enum in modules
      false
  """
  @spec non_terminating_modules() :: [module()]
  def non_terminating_modules do
    Map.keys(termination_blacklist())
  end

  @doc """
  Lists all non-terminating functions for a specific module.

  Returns a list of `{function, arity}` tuples that are non-terminating,
  or an empty list if the module has no non-terminating functions.

  ## Examples

      iex> Litmus.Stdlib.non_terminating_functions(Stream)
      [{:cycle, 1}, {:iterate, 2}, {:repeatedly, 1}, {:resource, 3}, {:unfold, 2}]

      iex> Litmus.Stdlib.non_terminating_functions(Enum)
      []
  """
  @spec non_terminating_functions(module()) :: [{atom(), arity()}]
  def non_terminating_functions(module) when is_atom(module) do
    Map.get(termination_blacklist(), module, [])
  end

  @doc """
  Exception whitelist for Elixir standard library.

  Maps known stdlib functions to the exceptions they can raise.

  ## Format

  ```elixir
  %{
    {Module, :function, arity} => %Litmus.Exceptions{
      errors: MapSet.new([ExceptionModule, ...]),
      non_errors: boolean()
    }
  }
  ```

  ## Philosophy

  - Only explicitly documented exceptions are tracked
  - Functions not in the whitelist are assumed to raise no exceptions
  - This is conservative - undocumented exceptions won't be tracked

  ## Examples

      iex> Litmus.Stdlib.get_exception_info({String, :to_integer!, 1})
      %{errors: MapSet.new([ArgumentError]), non_errors: false}

      iex> Litmus.Stdlib.get_exception_info({List, :first, 1})
      %{errors: MapSet.new([ArgumentError]), non_errors: false}
  """
  @spec exception_whitelist() :: %{mfa() => Litmus.Exceptions.exception_info()}
  def exception_whitelist do
    import Litmus.Exceptions

    %{
      # String module
      {String, :to_integer!, 1} => error(ArgumentError),
      {String, :to_float!, 1} => error(ArgumentError),
      {String, :to_existing_atom, 1} => error(ArgumentError),

      # List module
      {List, :first, 1} => error(ArgumentError),
      {List, :last, 1} => error(ArgumentError),

      # Map module
      {Map, :fetch!, 2} => error(KeyError),
      {Map, :get!, 2} => error(KeyError),
      {Map, :pop!, 2} => error(KeyError),
      {Map, :replace!, 3} => error(KeyError),
      {Map, :update!, 3} => error(KeyError),

      # Access module
      {Access, :fetch!, 2} => error(KeyError),
      {Access, :get!, 2} => error(KeyError),

      # Enum module
      {Enum, :at, 3} => error(Enum.OutOfBoundsError),
      {Enum, :fetch!, 2} => error(Enum.OutOfBoundsError),

      # Keyword module
      {Keyword, :fetch!, 2} => error(KeyError),
      {Keyword, :get!, 2} => error(KeyError),
      {Keyword, :pop!, 2} => error(KeyError),

      # Integer module
      {Integer, :parse, 1} => error(ArgumentError),
      {Integer, :parse, 2} => error(ArgumentError),
      {Integer, :to_string!, 1} => error(ArgumentError),
      {Integer, :to_charlist!, 1} => error(ArgumentError),

      # Float module
      {Float, :parse, 1} => error(ArgumentError),

      # Kernel module - pattern matching failures
      {Kernel, :hd, 1} => error(ArgumentError),
      {Kernel, :tl, 1} => error(ArgumentError),
      {Kernel, :elem, 2} => error(ArgumentError),
      {Kernel, :binary_part, 3} => error(ArgumentError),

      # Erlang BIFs - these are the compiled forms of Elixir functions
      {:erlang, :map_get, 2} => error(KeyError),

      # File.read!/1, File.read!/2 - but File is impure anyway
      # Process operations - throw/exit
      # These are tracked separately as non_errors
    }
  end

  @doc """
  Gets exception information for a stdlib function.

  Returns the exception info if the function is in the exception whitelist,
  or `nil` if no exception information is available (assumes no exceptions).

  ## Examples

      iex> info = Litmus.Stdlib.get_exception_info({String, :to_integer!, 1})
      iex> info.errors
      MapSet.new([ArgumentError])

      iex> Litmus.Stdlib.get_exception_info({Enum, :map, 2})
      nil
  """
  @spec get_exception_info(mfa()) :: Litmus.Exceptions.exception_info() | nil
  def get_exception_info(mfa) do
    Map.get(exception_whitelist(), mfa)
  end
end
