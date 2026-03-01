defmodule Apothecary.Bead do
  @moduledoc "Struct representing a Beads task from the bd CLI."

  @type t :: %__MODULE__{
          id: String.t() | nil,
          title: String.t() | nil,
          type: String.t() | nil,
          priority: integer() | nil,
          status: String.t() | nil,
          assigned_to: String.t() | nil,
          description: String.t() | nil,
          created_at: String.t() | nil,
          updated_at: String.t() | nil,
          parent: String.t() | nil,
          blockers: [String.t()],
          dependents: [String.t()]
        }

  defstruct [
    :id,
    :title,
    :type,
    :priority,
    :status,
    :assigned_to,
    :description,
    :created_at,
    :updated_at,
    :parent,
    blockers: [],
    dependents: []
  ]

  @doc "Parse a bead from a JSON-decoded map."
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      title: map["title"],
      type: map["type"],
      priority: map["priority"],
      status: map["status"],
      assigned_to: map["assigned_to"] || map["assignee"],
      description: map["description"],
      created_at: map["created_at"],
      updated_at: map["updated_at"],
      parent: map["parent"],
      blockers: map["blockers"] || [],
      dependents: map["dependents"] || []
    }
  end
end
