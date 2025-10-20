defmodule Litmus.Formatter do
  @moduledoc """
  Pretty printing utilities for types and effects.

  This module provides human-readable formatting for display purposes,
  primarily used by mix tasks and debugging tools.
  """

  @doc """
  Pretty prints a type for display.

  ## Examples

      iex> format_type(:int)
      "Int"

      iex> format_type({:type_var, :a})
      "a"

      iex> format_type({:function, :int, {:effect_empty}, :string})
      "Int -> ⟨⟩ String"
  """
  def format_type(type) do
    case type do
      :int ->
        "Int"

      :float ->
        "Float"

      :string ->
        "String"

      :bool ->
        "Bool"

      :atom ->
        "Atom"

      :pid ->
        "Pid"

      :reference ->
        "Ref"

      :any ->
        "Any"

      {:type_var, name} ->
        "#{name}"

      {:function, arg, effect, ret} ->
        "#{format_type(arg)} -> #{format_effect(effect)} #{format_type(ret)}"

      {:tuple, []} ->
        "{}"

      {:tuple, types} ->
        "{" <> Enum.map_join(types, ", ", &format_type/1) <> "}"

      {:list, type} ->
        "[#{format_type(type)}]"

      {:map, []} ->
        "%{}"

      {:map, pairs} ->
        content =
          Enum.map_join(pairs, ", ", fn {k, v} ->
            "#{format_type(k)} => #{format_type(v)}"
          end)

        "%{" <> content <> "}"

      {:union, types} ->
        Enum.map_join(types, " | ", &format_type/1)

      {:forall, vars, body} ->
        var_str =
          Enum.map_join(vars, " ", fn
            {:type_var, name} -> "#{name}"
            {:effect_var, name} -> "#{name}"
          end)

        "∀" <> var_str <> ". " <> format_type(body)

      _ ->
        inspect(type)
    end
  end

  @doc """
  Pretty prints an effect for display.

  ## Examples

      iex> format_effect({:effect_empty})
      "⟨⟩"

      iex> format_effect({:effect_label, :exn})
      "⟨exn⟩"

      iex> format_effect({:s, ["File.write/2"]})
      "⟨File.write/2⟩"

      iex> format_effect({:s, ["File.write/2", "IO.puts/1"]})
      "⟨File.write/2 | IO.puts/1⟩"

      iex> format_effect({:d, ["System.get_env/1"]})
      "⟨System.get_env/1⟩"

      iex> format_effect({:d, ["System.get_env/1", "Process.get/1"]})
      "⟨System.get_env/1 | Process.get/1⟩"

      iex> format_effect({:effect_row, :exn, {:s, ["File.write/2"]}})
      "⟨exn | File.write/2⟩"
  """
  def format_effect(effect) do
    case effect do
      {:effect_empty} -> "⟨⟩"
      {:effect_label, label} -> "⟨#{label}⟩"
      {:effect_var, name} -> "#{name}"
      {:effect_unknown} -> "¿"
      {:s, [single]} -> "⟨#{single}⟩"
      {:s, multiple} -> "⟨#{Enum.join(multiple, " | ")}⟩"
      {:d, [single]} -> "⟨#{single}⟩"
      {:d, multiple} -> "⟨#{Enum.join(multiple, " | ")}⟩"
      {:effect_row, label, tail} -> "⟨#{format_first_label(label)} | #{format_effect_tail(tail)}⟩"
      _ -> inspect(effect)
    end
  end

  defp format_first_label({:s, list}), do: Enum.join(list, " | ")
  defp format_first_label({:d, list}), do: Enum.join(list, " | ")
  defp format_first_label(label), do: "#{label}"

  defp format_effect_tail({:effect_empty}), do: ""
  defp format_effect_tail({:effect_label, label}), do: "#{label}"
  defp format_effect_tail({:effect_var, name}), do: "#{name}"
  defp format_effect_tail({:s, list}), do: Enum.join(list, " | ")
  defp format_effect_tail({:d, list}), do: Enum.join(list, " | ")

  defp format_effect_tail({:effect_row, label, tail}),
    do: "#{format_first_label(label)} | #{format_effect_tail(tail)}"

  defp format_effect_tail(other), do: format_effect(other)

  @doc """
  Formats a compact effect for display.

  ## Examples

      iex> format_compact_effect(:p)
      "p (pure)"

      iex> format_compact_effect(:d)
      "d (dependent)"

      iex> format_compact_effect(:l)
      "l (lambda)"

      iex> format_compact_effect(:s)
      "s (side effects)"

      iex> format_compact_effect(:exn)
      "e (exceptions)"

      iex> format_compact_effect(:n)
      "n (nif)"

      iex> format_compact_effect(:u)
      "u (unknown)"
  """
  def format_compact_effect(compact) do
    case compact do
      :p -> "p (pure)"
      :d -> "d (dependent)"
      :l -> "l (lambda)"
      :n -> "n (nif)"
      :s -> "s (side effects)"
      :exn -> "e (exceptions)"
      {:e, _} -> "e (exceptions)"
      :u -> "u (unknown)"
      other -> inspect(other)
    end
  end

  @doc """
  Formats a variable for display (used for error messages).
  """
  def format_var({:type_var, name}), do: "#{name}"
  def format_var({:effect_var, name}), do: "#{name}"
  def format_var(other), do: inspect(other)
end
