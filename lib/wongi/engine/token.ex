# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Wongi.Engine.Token do
  @moduledoc """
  An intermediate data structure representing a partial match.
  """
  alias Wongi.Engine.Beta
  alias Wongi.Engine.WME

  @type t() :: %__MODULE__{}

  @derive Inspect
  defstruct [:ref, :node_ref, :parents, :wme, :assignments]

  @spec new(any(), list(t()), WME.t() | nil, map()) :: t()
  @doc false
  def new(node, parents, wme, assignments \\ %{}) do
    %__MODULE__{
      ref: make_ref(),
      node_ref: Beta.ref(node),
      parents: MapSet.new(parents),
      wme: wme,
      assignments: assignments
    }
  end

  @doc "Returns all bound variables of the token."
  def assignments(%__MODULE__{assignments: assignments, parents: parents}) do
    Enum.map(parents, &assignments/1)
    |> Enum.reduce(%{}, &Map.merge/2)
    |> Map.merge(assignments)
  end

  @doc "Returns the value of a bound variable."
  @spec fetch(t(), atom()) :: {:ok, any()} | :error
  def fetch(%__MODULE__{assignments: assignments, parents: parents}, var) do
    case Map.fetch(assignments, var) do
      {:ok, _value} = ok ->
        ok

      :error ->
        Enum.reduce_while(parents, :error, fn parent, :error ->
          case fetch(parent, var) do
            :error -> {:cont, :error}
            value -> {:halt, value}
          end
        end)
    end
  end

  @doc false
  def fetch(
        %__MODULE__{} = token,
        var,
        extra_assignments
      ) do
    case Map.fetch(extra_assignments, var) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        fetch(token, var)
    end
  end

  @doc false
  def has_wme?(%__MODULE__{wme: wme}, wme), do: true
  def has_wme?(_, _), do: false

  @doc false
  def ancestral_wme?(%__MODULE__{wme: token_wme, parents: parents}, wme) do
    token_wme == wme || Enum.any?(parents, &ancestral_wme?(&1, wme))
  end

  @doc false
  def child_of?(%__MODULE__{parents: parents}, parent),
    do: MapSet.member?(parents, parent)

  @doc false
  def child_of_any?(%__MODULE__{} = token, parents),
    do: Enum.any?(parents, &child_of?(token, &1))

  @doc false
  # TODO: sort out token ownership to make this more straighforward; it is a bit
  # confusing that the token's owner node is one level deeper than you
  # intuitively think, and it makes NCC owner tracking difficult to reason about
  def lineage_of?(%__MODULE__{parents: parents} = token, other) do
    duplicate?(token, other) || Enum.any?(parents, &lineage_of?(&1, other))
  end

  defp duplicate?(token, other) do
    token.wme == other.wme && token.assignments == other.assignments &&
      parent_refs(token) == parent_refs(other)
  end

  defp parent_refs(%__MODULE__{parents: parents}) do
    Enum.map(parents, & &1.ref)
  end
end
