defmodule Apothecary.Ingredient do
  @moduledoc """
  Struct representing an ingredient (step within a concoction).
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          title: String.t() | nil,
          status: String.t() | nil,
          priority: integer() | nil,
          description: String.t() | nil,
          concoction_id: String.t() | nil,
          created_at: String.t() | nil,
          updated_at: String.t() | nil,
          notes: String.t() | nil,
          type: String.t(),
          parent: String.t() | nil,
          assigned_to: String.t() | nil,
          blockers: [String.t()],
          dependents: [String.t()]
        }

  defstruct [
    :id,
    :title,
    :status,
    :priority,
    :description,
    :concoction_id,
    :created_at,
    :updated_at,
    :notes,
    :assigned_to,
    type: "ingredient",
    parent: nil,
    blockers: [],
    dependents: []
  ]

  @doc "Build an Ingredient struct from a Mnesia record tuple."
  def from_record({:apothecary_ingredients, id, concoction_id, status, title, priority, data}) do
    %__MODULE__{
      id: id,
      concoction_id: concoction_id,
      status: status,
      title: title,
      priority: priority,
      parent: concoction_id,
      description: data[:description],
      notes: data[:notes],
      created_at: data[:created_at],
      updated_at: data[:updated_at],
      blockers: data[:blockers] || [],
      dependents: data[:dependents] || []
    }
  end

  @doc "Convert to a Mnesia record tuple."
  def to_record(%__MODULE__{} = t) do
    {:apothecary_ingredients, t.id, t.concoction_id, t.status, t.title, t.priority,
     %{
       description: t.description,
       notes: t.notes,
       created_at: t.created_at,
       updated_at: t.updated_at,
       blockers: t.blockers,
       dependents: t.dependents
     }}
  end
end
