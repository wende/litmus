defmodule Litmus.Support.BeamTestModule do
  @moduledoc """
  Test module for BEAM modification spike.

  This module is compiled separately so we can test runtime modification.
  """

  def sample_function(x) do
    x * 2
  end

  def another_function(a, b) do
    a + b
  end

  def pure_calculation(n) do
    n * n + n - 1
  end

  def fast_function(x) when is_integer(x) do
    x + 1
  end
end
