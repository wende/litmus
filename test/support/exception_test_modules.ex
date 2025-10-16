defmodule ExceptionTestModules do
  @moduledoc """
  Test modules for exception propagation testing.
  These need to be in a separate file so they can be compiled with debug_info.
  """

  defmodule PropagateExample do
    def level1(x), do: level2(x)
    def level2(x), do: level3(x)
    def level3(x), do: String.to_integer!(x)
  end

  defmodule ThrowPropagateExample do
    def caller(x), do: thrower(x)
    def thrower(x), do: if x > 10, do: throw(:too_big), else: x
  end

  defmodule MultipleCalleesExample do
    def caller(x, y) do
      a = String.to_integer!(x)
      b = Map.fetch!(y, :key)
      a + b
    end
  end

  defmodule DeepPropagateExample do
    def top(x), do: middle(x)
    def middle(x), do: bottom(x)
    def bottom(x), do: deeper(x)
    def deeper(x), do: String.to_integer!(x)
  end

  defmodule MutualRecursionExample do
    def ping(0), do: :done
    def ping(n), do: pong(n - 1)
    def pong(0), do: :done
    def pong(n), do: ping(n - 1)
  end

  defmodule UnknownExceptionExample do
    def caller(x), do: raiser(x)

    def raiser(exception) do
      :erlang.error(exception)
    end
  end

  defmodule PureExample do
    def pure_add(x, y), do: x + y
    def pure_mul(x, y), do: x * y
    def combined(x, y), do: pure_add(x, y) + pure_mul(x, y)
  end
end
