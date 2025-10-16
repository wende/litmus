defmodule Litmus.Exceptions do
  @moduledoc """
  Exception tracking for Elixir functions.

  This module provides functionality to track which exceptions can be raised by functions,
  distinguishing between:

  - **Typed exceptions** (`:error` class) - e.g., `ArgumentError`, `KeyError`
  - **Untyped exceptions** (`:throw` and `:exit` classes) - arbitrary values

  ## Exception Classes in Elixir/Erlang

  The BEAM VM has three exception classes, all using the same underlying mechanism:

  1. **`:error`** - Exceptions raised with `raise` / `erlang:error/1,2`
     - Include stack traces
     - Have typed exception modules (ArgumentError, KeyError, etc.)
     - Represent actual bugs/exceptional conditions

  2. **`:throw`** - Raised with `throw/1`
     - No stack trace
     - Used for non-local control flow
     - Arbitrary values (no type information)

  3. **`:exit`** - Raised with `exit/1`
     - No stack trace
     - Signal process termination
     - Arbitrary values (no type information)

  ## Data Structure

  We track exceptions using:

      @type exception_info :: %{
        errors: MapSet.t(module()) | :dynamic,
        non_errors: boolean()
      }

  - `errors`: Set of exception modules (e.g., `MapSet.new([ArgumentError, KeyError])`)
    or `:dynamic` if exceptions are raised dynamically
  - `non_errors`: Boolean flag indicating if `throw/1` or `exit/1` can be called

  ## Examples

      # Function that only raises ArgumentError
      %{
        errors: MapSet.new([ArgumentError]),
        non_errors: false
      }

      # Function that can throw
      %{
        errors: MapSet.new([]),
        non_errors: true
      }

      # Function that raises dynamic exceptions
      %{
        errors: :dynamic,
        non_errors: false
      }

      # Pure function (no exceptions)
      %{
        errors: MapSet.new([]),
        non_errors: false
      }
  """

  @type exception_info :: %{
          errors: MapSet.t(module()) | :dynamic,
          non_errors: boolean()
        }

  @type exception_result :: %{mfa() => exception_info()}

  @doc """
  Creates an empty exception info (no exceptions).
  """
  @spec empty() :: exception_info()
  def empty do
    %{
      errors: MapSet.new(),
      non_errors: false
    }
  end

  @doc """
  Creates exception info for a typed exception (`:error` class).

  ## Examples

      iex> Litmus.Exceptions.error(ArgumentError)
      %{errors: MapSet.new([ArgumentError]), non_errors: false}
  """
  @spec error(module()) :: exception_info()
  def error(exception_module) when is_atom(exception_module) do
    %{
      errors: MapSet.new([exception_module]),
      non_errors: false
    }
  end

  @doc """
  Creates exception info for dynamically-raised exceptions.

  Used when exceptions are raised dynamically (e.g., `raise variable`)
  and we can't determine the specific exception type statically.

  This represents a **lesser impurity** than :unknown purity level -
  we know exceptions are raised, just not which specific types.
  """
  @spec error_dynamic() :: exception_info()
  def error_dynamic do
    %{
      errors: :dynamic,
      non_errors: false
    }
  end

  @doc """
  Creates exception info for throw/exit (`:throw` or `:exit` class).

  ## Examples

      iex> Litmus.Exceptions.non_error()
      %{errors: MapSet.new([]), non_errors: true}
  """
  @spec non_error() :: exception_info()
  def non_error do
    %{
      errors: MapSet.new(),
      non_errors: true
    }
  end

  @doc """
  Merges two exception infos.

  Union of all possible exceptions from both sources.

  ## Examples

      iex> info1 = %{errors: MapSet.new([ArgumentError]), non_errors: false}
      iex> info2 = %{errors: MapSet.new([KeyError]), non_errors: true}
      iex> Litmus.Exceptions.merge(info1, info2)
      %{errors: MapSet.new([ArgumentError, KeyError]), non_errors: true}
  """
  @spec merge(exception_info(), exception_info()) :: exception_info()
  def merge(info1, info2) do
    %{
      errors: merge_errors(info1.errors, info2.errors),
      non_errors: info1.non_errors or info2.non_errors
    }
  end

  defp merge_errors(:dynamic, _), do: :dynamic
  defp merge_errors(_, :dynamic), do: :dynamic
  defp merge_errors(set1, set2), do: MapSet.union(set1, set2)

  @doc """
  Merges a list of exception infos.

  ## Examples

      iex> infos = [
      ...>   %{errors: MapSet.new([ArgumentError]), non_errors: false},
      ...>   %{errors: MapSet.new([KeyError]), non_errors: false},
      ...>   %{errors: MapSet.new([]), non_errors: true}
      ...> ]
      iex> Litmus.Exceptions.merge_all(infos)
      %{errors: MapSet.new([ArgumentError, KeyError]), non_errors: true}
  """
  @spec merge_all([exception_info()]) :: exception_info()
  def merge_all(infos) when is_list(infos) do
    Enum.reduce(infos, empty(), &merge/2)
  end

  @doc """
  Checks if an exception info can raise a specific exception module.

  Returns `false` if the exception module is definitely not raised.
  Returns `true` if it might be raised (including `:dynamic` case).

  ## Examples

      iex> info = %{errors: MapSet.new([ArgumentError, KeyError]), non_errors: false}
      iex> Litmus.Exceptions.can_raise?(info, ArgumentError)
      true
      iex> Litmus.Exceptions.can_raise?(info, RuntimeError)
      false

      iex> dynamic = %{errors: :dynamic, non_errors: false}
      iex> Litmus.Exceptions.can_raise?(dynamic, ArgumentError)
      true
  """
  @spec can_raise?(exception_info(), module()) :: boolean()
  def can_raise?(%{errors: :dynamic}, _exception_module), do: true
  def can_raise?(%{errors: errors}, exception_module) when is_atom(exception_module) do
    MapSet.member?(errors, exception_module)
  end

  @doc """
  Checks if an exception info can throw or exit.

  ## Examples

      iex> info = %{errors: MapSet.new([]), non_errors: true}
      iex> Litmus.Exceptions.can_throw_or_exit?(info)
      true

      iex> info = %{errors: MapSet.new([ArgumentError]), non_errors: false}
      iex> Litmus.Exceptions.can_throw_or_exit?(info)
      false
  """
  @spec can_throw_or_exit?(exception_info()) :: boolean()
  def can_throw_or_exit?(%{non_errors: non_errors}), do: non_errors

  @doc """
  Checks if an exception info represents a pure function (no exceptions).

  ## Examples

      iex> Litmus.Exceptions.pure?(Litmus.Exceptions.empty())
      true

      iex> info = %{errors: MapSet.new([ArgumentError]), non_errors: false}
      iex> Litmus.Exceptions.pure?(info)
      false
  """
  @spec pure?(exception_info()) :: boolean()
  def pure?(%{errors: errors, non_errors: non_errors}) do
    not non_errors and empty_errors?(errors)
  end

  defp empty_errors?(:dynamic), do: false
  defp empty_errors?(set), do: MapSet.size(set) == 0

  @doc """
  Subtracts caught exceptions from an exception info.

  Used when analyzing try/catch blocks - removes exceptions that are caught
  from the set that propagates to callers.

  ## Examples

      iex> info = %{errors: MapSet.new([ArgumentError, KeyError]), non_errors: true}
      iex> caught = %{errors: MapSet.new([ArgumentError]), non_errors: false}
      iex> Litmus.Exceptions.subtract(info, caught)
      %{errors: MapSet.new([KeyError]), non_errors: true}

      # Catching non_errors removes the flag
      iex> info = %{errors: MapSet.new([]), non_errors: true}
      iex> caught = %{errors: MapSet.new([]), non_errors: true}
      iex> Litmus.Exceptions.subtract(info, caught)
      %{errors: MapSet.new([]), non_errors: false}
  """
  @spec subtract(exception_info(), exception_info()) :: exception_info()
  def subtract(info, caught) do
    %{
      errors: subtract_errors(info.errors, caught.errors),
      non_errors: info.non_errors and not caught.non_errors
    }
  end

  defp subtract_errors(:dynamic, _), do: :dynamic
  defp subtract_errors(errors, :dynamic), do: errors
  defp subtract_errors(errors, caught), do: MapSet.difference(errors, caught)
end
