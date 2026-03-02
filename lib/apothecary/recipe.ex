defmodule Apothecary.Recipe do
  @moduledoc "Struct representing a recipe (recurring brew schedule)."

  @type t :: %__MODULE__{
          id: String.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          schedule: String.t() | nil,
          enabled: boolean(),
          priority: integer() | nil,
          last_run_at: String.t() | nil,
          next_run_at: String.t() | nil,
          created_at: String.t() | nil,
          updated_at: String.t() | nil,
          notes: String.t() | nil,
          type: String.t()
        }

  defstruct [
    :id,
    :title,
    :description,
    :schedule,
    :priority,
    :last_run_at,
    :next_run_at,
    :created_at,
    :updated_at,
    :notes,
    enabled: true,
    type: "recipe"
  ]

  @doc "Build a Recipe struct from a Mnesia record tuple."
  def from_record(
        {:apothecary_recipes, id, title, description, schedule, enabled, priority, data}
      ) do
    %__MODULE__{
      id: id,
      title: title,
      description: description,
      schedule: schedule,
      enabled: enabled,
      priority: priority,
      last_run_at: data[:last_run_at],
      next_run_at: data[:next_run_at],
      created_at: data[:created_at],
      updated_at: data[:updated_at],
      notes: data[:notes]
    }
  end

  @doc "Convert to a Mnesia record tuple."
  def to_record(%__MODULE__{} = r) do
    {:apothecary_recipes, r.id, r.title, r.description, r.schedule, r.enabled, r.priority,
     %{
       last_run_at: r.last_run_at,
       next_run_at: r.next_run_at,
       created_at: r.created_at,
       updated_at: r.updated_at,
       notes: r.notes
     }}
  end
end
