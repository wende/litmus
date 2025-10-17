defmodule Litmus.Effects.Registry do
  @moduledoc """
  Registry of known side-effectful functions in Elixir and Erlang standard libraries.

  This module tracks which functions have side effects and should be intercepted
  during effect handling. It leverages Litmus's existing purity analysis to identify
  side-effectful functions.
  """

  @doc """
  Returns true if the given MFA (module, function, arity) is a known effect.

  This uses a static registry of known effect modules and functions rather than
  dynamic purity analysis (which requires runtime results).
  """
  def effect?({module, function, _arity}) do
    # Check if the module is a known effect module
    effect_module?(module) or is_known_effect_function?(module, function)
  end

  defp is_known_effect_function?(module, function) do
    # Check if this specific function is known to be an effect
    # even if the module isn't entirely an effect module
    case {module, function} do
      # Process effects
      {Kernel, :send} -> true
      {Kernel, :spawn} -> true
      {Kernel, :spawn_link} -> true
      {Kernel, :spawn_monitor} -> true
      # Dynamic dispatch is an effect
      {Kernel, :apply} -> true
      # Exception-raising functions (can raise, so they're effectful!)
      # Can raise ArgumentError
      {Kernel, :hd} -> true
      # Can raise ArgumentError
      {Kernel, :tl} -> true
      # Can raise ArgumentError
      {Kernel, :elem} -> true
      # Can raise ArgumentError
      {Kernel, :put_elem} -> true
      # Can raise ArithmeticError
      {Kernel, :div} -> true
      # Can raise ArithmeticError
      {Kernel, :rem} -> true
      # Can raise ArgumentError
      {Kernel, :binary_part} -> true
      # Can raise ArgumentError
      {Kernel, :bit_size} -> true
      # Can raise ArgumentError
      {Kernel, :byte_size} -> true
      # Can raise BadMapError
      {Kernel, :map_size} -> true
      # Can raise ArgumentError
      {Kernel, :tuple_size} -> true
      # Exits process
      {Kernel, :exit} -> true
      # Throws value
      {Kernel, :throw} -> true
      # Note: raise/1,2 and reraise/2,3 are macros, not functions

      _ -> false
    end
  end

  @doc """
  Returns the effect category for a given MFA.

  Categories:
  - `:io` - Input/output operations
  - `:file` - File system operations
  - `:process` - Process creation, messaging, monitoring
  - `:network` - Network operations
  - `:ets` - ETS/DETS table operations
  - `:random` - Random number generation
  - `:time` - Time/clock access
  - `:system` - System information access
  - `:nif` - Native implemented functions
  - `:unknown` - Unknown or unclassified effects
  """
  def effect_category({module, function, _arity}) do
    case {module, function} do
      # File operations
      {File, fun}
      when fun in [
             :read,
             :read!,
             :write,
             :write!,
             :open,
             :close,
             :rm,
             :rm_rf,
             :mkdir,
             :mkdir_p,
             :cp,
             :cp_r,
             :ls,
             :stat,
             :exists?,
             :dir?,
             :regular?,
             :stream!,
             :chmod,
             :chown,
             :touch
           ] ->
        :file

      # IO operations
      {IO, fun}
      when fun in [
             :puts,
             :write,
             :gets,
             :read,
             :inspect,
             :warn,
             :getn,
             :binread,
             :binwrite,
             :stream
           ] ->
        :io

      # Process operations
      {Process, fun}
      when fun in [
             :send,
             :spawn,
             :spawn_link,
             :spawn_monitor,
             :exit,
             :register,
             :unregister,
             :whereis,
             :link,
             :unlink,
             :monitor,
             :demonitor,
             :flag,
             :send_after,
             :cancel_timer
           ] ->
        :process

      {Kernel, :send} ->
        :process

      {Kernel, :spawn} ->
        :process

      {Kernel, :spawn_link} ->
        :process

      {Kernel, :spawn_monitor} ->
        :process

      # Exception-raising Kernel functions
      {Kernel, fun}
      when fun in [
             :hd,
             :tl,
             :elem,
             :put_elem,
             :div,
             :rem,
             :binary_part,
             :bit_size,
             :byte_size,
             :map_size,
             :tuple_size,
             :exit,
             :throw
           ] ->
        :exception

      # Erlang process operations
      {:erlang, fun}
      when fun in [
             :send,
             :spawn,
             :spawn_link,
             :spawn_monitor,
             :spawn_opt,
             :register,
             :unregister,
             :whereis,
             :link,
             :unlink,
             :monitor,
             :demonitor,
             :send_after,
             :cancel_timer,
             :process_flag
           ] ->
        :process

      # Network operations
      {:gen_tcp, _} ->
        :network

      {:gen_udp, _} ->
        :network

      {:inet, _} ->
        :network

      {:ssl, _} ->
        :network

      # ETS operations
      {:ets, fun}
      when fun in [
             :new,
             :insert,
             :lookup,
             :delete,
             :delete_all_objects,
             :match,
             :select,
             :tab2list,
             :info,
             :rename
           ] ->
        :ets

      {:dets, fun}
      when fun in [:open_file, :close, :insert, :lookup, :delete, :match, :select, :sync, :info] ->
        :ets

      # Random operations
      {:rand, _} ->
        :random

      {:random, _} ->
        :random

      # Time operations
      {:erlang, fun}
      when fun in [
             :now,
             :system_time,
             :monotonic_time,
             :timestamp,
             :time_offset,
             :universaltime,
             :localtime
           ] ->
        :time

      {System, fun} when fun in [:system_time, :monotonic_time, :os_time, :unique_integer] ->
        :time

      # System operations
      {System, fun} when fun in [:get_env, :put_env, :delete_env, :cmd, :halt, :stop] ->
        :system

      {:os, fun} when fun in [:getenv, :putenv, :unsetenv, :cmd, :system_time] ->
        :system

      # Port operations
      {Port, _} ->
        :process

      {:erlang, fun} when fun in [:open_port, :port_close, :port_command, :port_connect] ->
        :process

      # Code loading/compilation
      {Code, fun}
      when fun in [
             :compile_file,
             :compile_string,
             :eval_file,
             :eval_string,
             :require_file,
             :load_file
           ] ->
        :system

      # Agent operations
      {Agent, _} ->
        :process

      # Task operations
      {Task, fun} when fun in [:start, :start_link, :async, :async_stream] ->
        :process

      # GenServer operations
      {GenServer, fun} when fun in [:start, :start_link, :call, :cast, :stop] ->
        :process

      # Supervisor operations
      {Supervisor, fun}
      when fun in [:start_link, :start_child, :terminate_child, :delete_child, :restart_child] ->
        :process

      # Application operations
      {Application, fun} when fun in [:start, :stop, :load, :unload, :put_env, :delete_env] ->
        :system

      # Logger operations
      {Logger, _} ->
        :io

      # Default: unknown
      _ ->
        :unknown
    end
  end

  @doc """
  Returns a list of all registered effect modules.
  """
  def effect_modules do
    [
      File,
      IO,
      Process,
      Port,
      Agent,
      Task,
      GenServer,
      Supervisor,
      Application,
      Logger,
      System,
      Code,
      :gen_tcp,
      :gen_udp,
      :inet,
      :ssl,
      :ets,
      :dets,
      :rand,
      :random,
      :os,
      :erlang
    ]
  end

  @doc """
  Checks if a module is known to contain effects.
  """
  def effect_module?(module) do
    module in effect_modules()
  end
end
