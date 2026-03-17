defmodule Apothecary.Task do
  @moduledoc """
  Struct representing a task (step within a worktree).
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          title: String.t() | nil,
          status: String.t() | nil,
          priority: integer() | nil,
          description: String.t() | nil,
          worktree_id: String.t() | nil,
          created_at: String.t() | nil,
          updated_at: String.t() | nil,
          notes: String.t() | nil,
          kind: String.t(),
          parent_question_id: String.t() | nil,
          agent_md: String.t() | nil,
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
    :worktree_id,
    :created_at,
    :updated_at,
    :notes,
    :assigned_to,
    :agent_md,
    kind: "task",
    parent_question_id: nil,
    type: "task",
    parent: nil,
    blockers: [],
    dependents: []
  ]

  def is_readonly_kind?(kind) when kind in ["question", "plan"], do: true
  def is_readonly_kind?(_), do: false

  @doc "Build a Task struct from a Mnesia record tuple."
  def from_record({:apothecary_tasks, id, worktree_id, status, title, priority, data}) do
    %__MODULE__{
      id: id,
      worktree_id: worktree_id,
      status: status,
      title: title,
      priority: priority,
      parent: worktree_id,
      description: data[:description],
      notes: data[:notes],
      kind: data[:kind] || "task",
      parent_question_id: data[:parent_question_id],
      agent_md: data[:agent_md],
      created_at: data[:created_at],
      updated_at: data[:updated_at],
      blockers: data[:blockers] || [],
      dependents: data[:dependents] || []
    }
  end

  @doc "Convert to a Mnesia record tuple."
  def to_record(%__MODULE__{} = t) do
    {:apothecary_tasks, t.id, t.worktree_id, t.status, t.title, t.priority,
     %{
       description: t.description,
       notes: t.notes,
       kind: t.kind,
       parent_question_id: t.parent_question_id,
       agent_md: t.agent_md,
       created_at: t.created_at,
       updated_at: t.updated_at,
       blockers: t.blockers,
       dependents: t.dependents
     }}
  end
end
