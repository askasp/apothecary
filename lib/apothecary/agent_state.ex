defmodule Apothecary.AgentState do
  @moduledoc "Struct representing the state of a swarm agent for the dashboard."

  @type status :: :idle | :working | :starting | :error

  @type t :: %__MODULE__{
          id: integer(),
          worktree_path: String.t() | nil,
          branch: String.t() | nil,
          current_task: Apothecary.Bead.t() | nil,
          status: status(),
          pid: pid() | nil,
          output: [String.t()],
          started_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :worktree_path,
    :branch,
    :current_task,
    :pid,
    :started_at,
    status: :idle,
    output: []
  ]
end
