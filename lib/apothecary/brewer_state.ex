defmodule Apothecary.BrewerState do
  @moduledoc "Struct representing the state of a brewer for the dashboard."

  @type status :: :idle | :working | :starting | :error

  @type t :: %__MODULE__{
          id: integer(),
          project_dir: String.t() | nil,
          worktree_path: String.t() | nil,
          branch: String.t() | nil,
          current_concoction: Apothecary.Concoction.t() | nil,
          status: status(),
          pid: pid() | nil,
          output: [String.t()],
          started_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :project_dir,
    :worktree_path,
    :branch,
    :current_concoction,
    :pid,
    :started_at,
    status: :idle,
    output: []
  ]
end
