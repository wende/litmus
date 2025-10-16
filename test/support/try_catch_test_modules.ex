defmodule TryCatchTestModules do
  @moduledoc """
  Test modules for try/catch exception tracking.
  """

  defmodule SimpleCatch do
    @doc """
    Catches ArgumentError, so it shouldn't propagate to callers.
    """
    def safe_hd(list) do
      try do
        hd(list)
      catch
        :error, %ArgumentError{} -> :empty
      end
    end
  end

  defmodule PartialCatch do
    @doc """
    Catches ArgumentError but KeyError still propagates.
    """
    def mixed(list, map) do
      try do
        x = hd(list)  # Raises ArgumentError
        y = Map.fetch!(map, :key)  # Raises KeyError
        {x, y}
      catch
        :error, %ArgumentError{} -> :caught_arg_error
      end
    end
  end

  defmodule CatchAll do
    @doc """
    Catches all errors, so no exceptions propagate.
    """
    def safe_call(fun) do
      try do
        fun.()
      catch
        :error, _ -> :error
      end
    end
  end

  defmodule CatchThrow do
    @doc """
    Catches throw, so non_errors shouldn't propagate.
    """
    def catch_throw(value) do
      try do
        if value > 10, do: throw(:too_big), else: value
      catch
        :throw, _ -> :caught
      end
    end
  end

  defmodule NoCatch do
    @doc """
    No catch block, exceptions propagate normally.
    """
    def unsafe_hd(list) do
      hd(list)  # ArgumentError propagates
    end
  end

  defmodule NestedTryCatch do
    @doc """
    Nested try/catch blocks.
    """
    def nested(list1, list2) do
      try do
        x = hd(list1)  # ArgumentError

        y =
          try do
            hd(list2)  # ArgumentError caught by inner try
          catch
            :error, %ArgumentError{} -> :inner_caught
          end

        {x, y}
      catch
        :error, %ArgumentError{} -> :outer_caught
      end
    end
  end
end
