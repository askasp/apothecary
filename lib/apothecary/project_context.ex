defmodule Apothecary.ProjectContext do
  @moduledoc "Struct representing a shared project context entry."

  @type t :: %__MODULE__{
          project_id: String.t(),
          category: String.t(),
          content: String.t(),
          updated_at: String.t() | nil,
          updated_by: String.t() | nil
        }

  defstruct [:project_id, :category, :content, :updated_at, :updated_by]

  @doc "Build a ProjectContext struct from a Mnesia record tuple."
  def from_record({:apothecary_project_context, {project_id, category}, _project_id, data}) do
    %__MODULE__{
      project_id: project_id,
      category: category,
      content: data[:content],
      updated_at: data[:updated_at],
      updated_by: data[:updated_by]
    }
  end
end
