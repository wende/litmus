defmodule Litmus.Types.Unification do
  @moduledoc """
  Unification algorithm for types and effects.

  Implements Robinson's unification algorithm extended with effect row unification,
  following the approach from Koka that enables principal type inference.

  The key insight is that duplicate labels in effect rows enable unique solutions
  to constraints like ⟨exn | μ⟩ ∼ ⟨exn⟩ (solution: μ = ⟨⟩).
  """

  alias Litmus.Types.Substitution
  alias Litmus.Formatter

  @type unify_result :: {:ok, Substitution.t()} | {:error, term()}

  @doc """
  Unifies two types, producing a substitution that makes them equal.

  ## Examples

      iex> unify({:type_var, :a}, :int)
      {:ok, %{{:type_var, :a} => :int}}

      iex> unify(:int, :string)
      {:error, {:cannot_unify, :int, :string}}
  """
  def unify(type1, type2) do
    unify_types(type1, type2, Substitution.empty())
  end

  # Main unification algorithm
  defp unify_types(t1, t2, subst) do
    # Apply current substitutions
    t1_subst = Substitution.apply_subst(subst, t1)
    t2_subst = Substitution.apply_subst(subst, t2)

    case {t1_subst, t2_subst} do
      # Identical types
      {t, t} -> {:ok, subst}

      # Type variable on left
      {{:type_var, _} = var, type} ->
        unify_variable(var, type, subst)

      # Type variable on right
      {type, {:type_var, _} = var} ->
        unify_variable(var, type, subst)

      # Function types
      {{:function, arg1, eff1, ret1}, {:function, arg2, eff2, ret2}} ->
        with {:ok, subst1} <- unify_types(arg1, arg2, subst),
             {:ok, subst2} <- unify_effects(eff1, eff2, subst1),
             {:ok, subst3} <- unify_types(ret1, ret2, subst2) do
          {:ok, subst3}
        end

      # Tuple types
      {{:tuple, types1}, {:tuple, types2}} when length(types1) == length(types2) ->
        unify_list(types1, types2, subst)

      # List types
      {{:list, elem1}, {:list, elem2}} ->
        unify_types(elem1, elem2, subst)

      # Map types (simplified - would need more complex handling in practice)
      {{:map, pairs1}, {:map, pairs2}} when length(pairs1) == length(pairs2) ->
        # Sort by key for comparison
        sorted1 = Enum.sort_by(pairs1, fn {k, _} -> Formatter.format_type(k) end)
        sorted2 = Enum.sort_by(pairs2, fn {k, _} -> Formatter.format_type(k) end)
        unify_pairs(sorted1, sorted2, subst)

      # Union types (simplified)
      {{:union, _types1}, {:union, _types2}} ->
        # Union unification is complex; for now, only exact matches
        if t1_subst == t2_subst do
          {:ok, subst}
        else
          {:error, {:cannot_unify_unions, t1_subst, t2_subst}}
        end

      # Forall types
      {{:forall, vars1, body1}, {:forall, vars2, body2}} when length(vars1) == length(vars2) ->
        # Rename variables to be consistent
        {renamed_body2, _renaming} = rename_bound_vars(vars2, body2, vars1)
        unify_types(body1, renamed_body2, subst)

      # Different types
      _ ->
        {:error, {:cannot_unify, t1_subst, t2_subst}}
    end
  end

  @doc """
  Unifies two effects, handling row polymorphism correctly.

  The algorithm handles duplicate labels and finds principal unifiers.

  ## Examples

      iex> unify_effect({:effect_label, :io}, {:effect_label, :io})
      {:ok, %{}}

      iex> unify_effect({:effect_row, :exn, {:effect_var, :e}}, {:effect_label, :exn})
      {:ok, %{{:effect_var, :e} => {:effect_empty}}}
  """
  def unify_effect(eff1, eff2) do
    unify_effects(eff1, eff2, Substitution.empty())
  end

  defp unify_effects(e1, e2, subst) do
    # Apply current substitutions
    e1_subst = Substitution.apply_subst(subst, e1)
    e2_subst = Substitution.apply_subst(subst, e2)

    case {e1_subst, e2_subst} do
      # Identical effects
      {e, e} -> {:ok, subst}

      # Effect variable on left
      {{:effect_var, _} = var, effect} ->
        unify_effect_variable(var, effect, subst)

      # Effect variable on right
      {effect, {:effect_var, _} = var} ->
        unify_effect_variable(var, effect, subst)

      # Empty effects
      {{:effect_empty}, {:effect_empty}} ->
        {:ok, subst}

      # Single labels
      {{:effect_label, l1}, {:effect_label, l2}} when l1 == l2 ->
        {:ok, subst}

      # Row with empty
      {{:effect_row, _l, _tail}, {:effect_empty}} ->
        {:error, {:cannot_unify_non_empty_with_empty, e1_subst, e2_subst}}

      {{:effect_empty}, {:effect_row, _l, _tail}} ->
        {:error, {:cannot_unify_non_empty_with_empty, e1_subst, e2_subst}}

      # Row with single label
      {{:effect_row, l1, tail}, {:effect_label, l2}} when l1 == l2 ->
        unify_effects(tail, {:effect_empty}, subst)

      {{:effect_label, l1}, {:effect_row, l2, tail}} when l1 == l2 ->
        unify_effects({:effect_empty}, tail, subst)

      # Two rows - this is the complex case
      {{:effect_row, l1, tail1}, {:effect_row, l2, tail2}} ->
        unify_rows(l1, tail1, l2, tail2, subst)

      # Unknown effect
      {{:effect_unknown}, _} ->
        {:ok, subst}  # Unknown unifies with anything

      {_, {:effect_unknown}} ->
        {:ok, subst}  # Unknown unifies with anything

      # Cannot unify
      _ ->
        {:error, {:cannot_unify_effects, e1_subst, e2_subst}}
    end
  end

  # Unify two effect rows
  defp unify_rows(l1, tail1, l2, tail2, subst) when l1 == l2 do
    # Same label, unify tails
    unify_effects(tail1, tail2, subst)
  end

  defp unify_rows(l1, tail1, l2, tail2, subst) do
    # Different labels - try to find l1 in the second row and vice versa
    case find_and_remove_label(l1, {:effect_row, l2, tail2}) do
      {:found, rest2} ->
        # l1 was found in row2, continue with tails
        with {:ok, subst1} <- unify_effects(tail1, rest2, subst) do
          {:ok, subst1}
        end

      :not_found ->
        case {tail1, tail2} do
          {{:effect_var, _} = var, _} ->
            # tail1 is a variable, it should contain l2
            extended = {:effect_row, l2, var}
            unify_effects({:effect_row, l1, extended}, {:effect_row, l2, tail2}, subst)

          {_, {:effect_var, _} = var} ->
            # tail2 is a variable, it should contain l1
            extended = {:effect_row, l1, var}
            unify_effects({:effect_row, l1, tail1}, {:effect_row, l2, extended}, subst)

          _ ->
            {:error, {:incompatible_effect_rows, {:effect_row, l1, tail1}, {:effect_row, l2, tail2}}}
        end
    end
  end

  # Find and remove a label from an effect row
  defp find_and_remove_label(label, {:effect_row, l, tail}) when label == l do
    {:found, tail}
  end

  defp find_and_remove_label(label, {:effect_row, l, tail}) do
    case find_and_remove_label(label, tail) do
      {:found, rest} -> {:found, {:effect_row, l, rest}}
      :not_found -> :not_found
    end
  end

  defp find_and_remove_label(label, {:effect_label, l}) when label == l do
    {:found, {:effect_empty}}
  end

  defp find_and_remove_label(_label, _effect) do
    :not_found
  end

  # Unify a variable with a type
  defp unify_variable(var, type, subst) do
    if occurs_check(var, type, subst) do
      {:error, {:occurs_check_failed, var, type}}
    else
      {:ok, Substitution.add(subst, var, type)}
    end
  end

  # Unify an effect variable with an effect
  defp unify_effect_variable(var, effect, subst) do
    if occurs_check(var, effect, subst) do
      {:error, {:occurs_check_failed, var, effect}}
    else
      {:ok, Substitution.add(subst, var, effect)}
    end
  end

  # Occurs check to prevent infinite types
  defp occurs_check(var, type, subst) do
    type_subst = Substitution.apply_subst(subst, type)
    occurs_in?(var, type_subst)
  end

  defp occurs_in?(var, var), do: true
  defp occurs_in?(var, {:function, arg, eff, ret}) do
    occurs_in?(var, arg) or occurs_in?(var, eff) or occurs_in?(var, ret)
  end
  defp occurs_in?(var, {:tuple, types}) do
    Enum.any?(types, &occurs_in?(var, &1))
  end
  defp occurs_in?(var, {:list, type}) do
    occurs_in?(var, type)
  end
  defp occurs_in?(var, {:map, pairs}) do
    Enum.any?(pairs, fn {k, v} -> occurs_in?(var, k) or occurs_in?(var, v) end)
  end
  defp occurs_in?(var, {:union, types}) do
    Enum.any?(types, &occurs_in?(var, &1))
  end
  defp occurs_in?(var, {:forall, _vars, body}) do
    occurs_in?(var, body)
  end
  defp occurs_in?(var, {:effect_row, _label, tail}) do
    occurs_in?(var, tail)
  end
  defp occurs_in?(_var, _type), do: false

  # Unify lists of types pairwise
  defp unify_list([], [], subst), do: {:ok, subst}
  defp unify_list([t1 | rest1], [t2 | rest2], subst) do
    with {:ok, subst1} <- unify_types(t1, t2, subst),
         {:ok, subst2} <- unify_list(rest1, rest2, subst1) do
      {:ok, subst2}
    end
  end

  # Unify pairs of key-value types
  defp unify_pairs([], [], subst), do: {:ok, subst}
  defp unify_pairs([{k1, v1} | rest1], [{k2, v2} | rest2], subst) do
    with {:ok, subst1} <- unify_types(k1, k2, subst),
         {:ok, subst2} <- unify_types(v1, v2, subst1),
         {:ok, subst3} <- unify_pairs(rest1, rest2, subst2) do
      {:ok, subst3}
    end
  end

  # Rename bound variables for alpha-equivalence
  defp rename_bound_vars(old_vars, body, new_vars) do
    renaming = Enum.zip(old_vars, new_vars) |> Enum.into(%{})
    renamed_body = apply_renaming(body, renaming)
    {renamed_body, renaming}
  end

  defp apply_renaming(type, renaming) do
    case type do
      {:type_var, _} = var ->
        Map.get(renaming, var, var)

      {:effect_var, _} = var ->
        Map.get(renaming, var, var)

      {:function, arg, eff, ret} ->
        {:function,
         apply_renaming(arg, renaming),
         apply_renaming(eff, renaming),
         apply_renaming(ret, renaming)}

      {:tuple, types} ->
        {:tuple, Enum.map(types, &apply_renaming(&1, renaming))}

      {:list, elem_type} ->
        {:list, apply_renaming(elem_type, renaming)}

      {:effect_row, label, tail} ->
        {:effect_row, label, apply_renaming(tail, renaming)}

      {:forall, vars, body} ->
        # Don't rename inside new quantifiers
        {:forall, vars, body}

      other ->
        other
    end
  end
end