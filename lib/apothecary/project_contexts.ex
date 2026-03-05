defmodule Apothecary.ProjectContexts do
  @moduledoc """
  CRUD operations for shared project context backed by Mnesia.

  Stores per-project knowledge (architecture, conventions, patterns, etc.)
  that agents can read and write to build shared understanding across worktrees.
  """

  alias Apothecary.ProjectContext

  @doc "List all context entries for a project."
  @spec list(String.t()) :: [ProjectContext.t()]
  def list(project_id) do
    :mnesia.dirty_index_read(:apothecary_project_context, project_id, :project_id)
    |> Enum.map(&ProjectContext.from_record/1)
    |> Enum.sort_by(& &1.category)
  end

  @doc "Get a specific context entry by project_id and category."
  @spec get(String.t(), String.t()) :: {:ok, ProjectContext.t()} | {:error, :not_found}
  def get(project_id, category) do
    case :mnesia.dirty_read(:apothecary_project_context, {project_id, category}) do
      [record] -> {:ok, ProjectContext.from_record(record)}
      [] -> {:error, :not_found}
    end
  end

  @doc "Save a context entry (creates or updates)."
  @spec save(String.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, ProjectContext.t()} | {:error, term()}
  def save(project_id, category, content, updated_by \\ nil) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    record =
      {:apothecary_project_context, {project_id, category}, project_id,
       %{
         content: content,
         updated_at: now,
         updated_by: updated_by
       }}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} ->
        {:ok, ProjectContext.from_record(record)}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Delete a context entry."
  @spec delete(String.t(), String.t()) :: :ok | {:error, :not_found}
  def delete(project_id, category) do
    key = {project_id, category}

    case :mnesia.transaction(fn ->
           case :mnesia.read(:apothecary_project_context, key) do
             [_] -> :mnesia.delete({:apothecary_project_context, key})
             [] -> :mnesia.abort(:not_found)
           end
         end) do
      {:atomic, :ok} -> :ok
      {:aborted, :not_found} -> {:error, :not_found}
      {:aborted, reason} -> {:error, reason}
    end
  end
end
