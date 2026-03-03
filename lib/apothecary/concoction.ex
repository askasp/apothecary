defmodule Apothecary.Concoction do
  @moduledoc "Struct representing a concoction (unit of work/PR)."

  @type t :: %__MODULE__{
          id: String.t() | nil,
          project_id: String.t() | nil,
          title: String.t() | nil,
          status: String.t() | nil,
          priority: integer() | nil,
          description: String.t() | nil,
          git_path: String.t() | nil,
          git_branch: String.t() | nil,
          parent_concoction_id: String.t() | nil,
          assigned_brewer_id: integer() | nil,
          created_at: String.t() | nil,
          updated_at: String.t() | nil,
          pr_url: String.t() | nil,
          notes: String.t() | nil,
          mcp_servers: map() | nil,
          type: String.t(),
          parent: String.t() | nil,
          assigned_to: String.t() | nil,
          blockers: [String.t()],
          dependents: [String.t()]
        }

  defstruct [
    :id,
    :project_id,
    :title,
    :status,
    :priority,
    :description,
    :git_path,
    :git_branch,
    :parent_concoction_id,
    :assigned_brewer_id,
    :created_at,
    :updated_at,
    :pr_url,
    :notes,
    :mcp_servers,
    type: "concoction",
    parent: nil,
    assigned_to: nil,
    blockers: [],
    dependents: []
  ]

  @doc "Build a Concoction struct from a Mnesia record tuple."
  def from_record(
        {:apothecary_concoctions, id, project_id, status, title, priority, git_path, git_branch,
         parent_concoction_id, assigned_brewer_id, data}
      ) do
    %__MODULE__{
      id: id,
      project_id: project_id,
      status: status,
      title: title,
      priority: priority,
      git_path: git_path,
      git_branch: git_branch,
      parent_concoction_id: parent_concoction_id,
      assigned_brewer_id: assigned_brewer_id,
      parent: parent_concoction_id,
      assigned_to: assigned_brewer_id && "brewer-#{assigned_brewer_id}",
      description: data[:description],
      notes: data[:notes],
      pr_url: data[:pr_url],
      mcp_servers: data[:mcp_servers],
      created_at: data[:created_at],
      updated_at: data[:updated_at],
      blockers: data[:blockers] || [],
      dependents: data[:dependents] || []
    }
  end

  @doc "Convert to a Mnesia record tuple."
  def to_record(%__MODULE__{} = wt) do
    {:apothecary_concoctions, wt.id, wt.project_id, wt.status, wt.title, wt.priority,
     wt.git_path, wt.git_branch, wt.parent_concoction_id, wt.assigned_brewer_id,
     %{
       description: wt.description,
       notes: wt.notes,
       pr_url: wt.pr_url,
       mcp_servers: wt.mcp_servers,
       created_at: wt.created_at,
       updated_at: wt.updated_at,
       blockers: wt.blockers,
       dependents: wt.dependents
     }}
  end
end
