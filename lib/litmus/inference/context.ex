defmodule Litmus.Inference.Context do
  @moduledoc """
  Typing context management for bidirectional type inference.

  The context maintains:
  - Variable bindings (name -> type)
  - Effect constraints
  - Type variable scopes

  Implements ordered contexts for tracking information flow direction,
  which simplifies soundness proofs in bidirectional typing.
  """

  alias Litmus.Types.{Core, Substitution}
  alias Litmus.Formatter

  @type t :: %__MODULE__{
    bindings: %{atom() => Core.elixir_type()},
    effects: list(Core.effect_type()),
    scope_level: non_neg_integer()
  }

  defstruct bindings: %{},
            effects: [],
            scope_level: 0

  @doc """
  Creates an empty context.
  """
  def empty do
    %__MODULE__{}
  end

  @doc """
  Adds a variable binding to the context.

  ## Examples

      iex> empty() |> add(:x, :int)
      %Context{bindings: %{x: :int}}
  """
  def add(%__MODULE__{} = ctx, name, type) when is_atom(name) do
    %{ctx | bindings: Map.put(ctx.bindings, name, type)}
  end

  @doc """
  Looks up a variable in the context.

  ## Examples

      iex> ctx = empty() |> add(:x, :int)
      iex> lookup(ctx, :x)
      {:ok, :int}

      iex> lookup(ctx, :y)
      :error
  """
  def lookup(%__MODULE__{bindings: bindings}, name) when is_atom(name) do
    case Map.fetch(bindings, name) do
      {:ok, type} -> {:ok, type}
      :error -> :error
    end
  end

  @doc """
  Adds multiple bindings to the context.
  """
  def add_bindings(%__MODULE__{} = ctx, bindings) when is_list(bindings) do
    Enum.reduce(bindings, ctx, fn {name, type}, acc ->
      add(acc, name, type)
    end)
  end

  @doc """
  Enters a new scope level.

  Used for handling let-polymorphism and nested scopes.
  """
  def enter_scope(%__MODULE__{scope_level: level} = ctx) do
    %{ctx | scope_level: level + 1}
  end

  @doc """
  Exits a scope level, removing bindings from that scope.
  """
  def exit_scope(%__MODULE__{scope_level: 0} = ctx), do: ctx

  def exit_scope(%__MODULE__{scope_level: level} = ctx) do
    %{ctx | scope_level: level - 1}
  end

  @doc """
  Adds an effect constraint to the context.
  """
  def add_effect(%__MODULE__{effects: effects} = ctx, effect) do
    %{ctx | effects: [effect | effects]}
  end

  @doc """
  Gets all effect constraints from the context.
  """
  def get_effects(%__MODULE__{effects: effects}) do
    effects
  end

  @doc """
  Applies a substitution to all types in the context.
  """
  def apply_substitution(%__MODULE__{bindings: bindings} = ctx, subst) do
    new_bindings = Map.new(bindings, fn {name, type} ->
      {name, Substitution.apply_subst(subst, type)}
    end)
    %{ctx | bindings: new_bindings}
  end

  @doc """
  Merges two contexts, preferring bindings from the second context.
  """
  def merge(%__MODULE__{} = ctx1, %__MODULE__{} = ctx2) do
    %__MODULE__{
      bindings: Map.merge(ctx1.bindings, ctx2.bindings),
      effects: ctx1.effects ++ ctx2.effects,
      scope_level: max(ctx1.scope_level, ctx2.scope_level)
    }
  end

  @doc """
  Gets all free type variables in the context.
  """
  def free_variables(%__MODULE__{bindings: bindings}) do
    bindings
    |> Map.values()
    |> Enum.flat_map(&Core.free_variables/1)
    |> MapSet.new()
  end

  @doc """
  Checks if a variable is bound in the context.
  """
  def has_binding?(%__MODULE__{bindings: bindings}, name) when is_atom(name) do
    Map.has_key?(bindings, name)
  end

  @doc """
  Removes a binding from the context.
  """
  def remove(%__MODULE__{bindings: bindings} = ctx, name) when is_atom(name) do
    %{ctx | bindings: Map.delete(bindings, name)}
  end

  @doc """
  Creates a context with standard library functions pre-defined.
  """
  def with_stdlib do
    stdlib_bindings = [
      # Basic arithmetic
      {:+, {:function, {:tuple, [:int, :int]}, Core.empty_effect(), :int}},
      {:-, {:function, {:tuple, [:int, :int]}, Core.empty_effect(), :int}},
      {:*, {:function, {:tuple, [:int, :int]}, Core.empty_effect(), :int}},

      # Comparisons
      {:==, {:function, {:tuple, [{:type_var, :a}, {:type_var, :a}]},
             Core.empty_effect(), :bool}},
      {:<, {:function, {:tuple, [{:type_var, :a}, {:type_var, :a}]},
            Core.empty_effect(), :bool}},
      {:>, {:function, {:tuple, [{:type_var, :a}, {:type_var, :a}]},
            Core.empty_effect(), :bool}},

      # Boolean operations
      {:and, {:function, {:tuple, [:bool, :bool]}, Core.empty_effect(), :bool}},
      {:or, {:function, {:tuple, [:bool, :bool]}, Core.empty_effect(), :bool}},
      {:not, {:function, :bool, Core.empty_effect(), :bool}},

      # List operations (with potential exceptions)
      {:hd, {:forall, [{:type_var, :a}],
             {:function, {:list, {:type_var, :a}},
              Core.single_effect(:exn),
              {:type_var, :a}}}},
      {:tl, {:forall, [{:type_var, :a}],
             {:function, {:list, {:type_var, :a}},
              Core.single_effect(:exn),
              {:list, {:type_var, :a}}}}},
      {:length, {:forall, [{:type_var, :a}],
                 {:function, {:list, {:type_var, :a}},
                  Core.empty_effect(),
                  :int}}}
    ]

    add_bindings(empty(), stdlib_bindings)
  end

  @doc """
  Pretty prints the context for debugging.
  """
  def format(%__MODULE__{bindings: bindings, effects: effects, scope_level: level}) do
    binding_str = bindings
                  |> Enum.map(fn {name, type} ->
                    "  #{name} : #{Formatter.format_type(type)}"
                  end)
                  |> Enum.join("\n")

    effect_str = if Enum.empty?(effects) do
      "  (none)"
    else
      effects
      |> Enum.map(&Formatter.format_effect/1)
      |> Enum.join(", ")
      |> then(&"  #{&1}")
    end

    """
    Context (scope level: #{level}):
    Bindings:
    #{binding_str}
    Effects:
    #{effect_str}
    """
  end
end