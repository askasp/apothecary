defmodule Apothecary.Projects do
  @moduledoc """
  CRUD operations for projects backed by Mnesia.

  Each project represents a git repository that Apothecary manages.
  Projects are independent — each has its own concoctions, worktrees, and settings.
  """

  require Logger

  alias Apothecary.Project

  @pubsub Apothecary.PubSub
  @topic "projects:updates"

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @doc "List all projects."
  def list do
    :mnesia.dirty_match_object({:apothecary_projects, :_, :_, :_, :_, :_})
    |> Enum.map(&Project.from_record/1)
    |> Enum.sort_by(& &1.name)
  end

  @doc "List active projects."
  def list_active do
    :mnesia.dirty_match_object({:apothecary_projects, :_, :_, :_, :active, :_})
    |> Enum.map(&Project.from_record/1)
    |> Enum.sort_by(& &1.name)
  end

  @doc "Get a project by ID."
  def get(id) do
    case :mnesia.dirty_read(:apothecary_projects, id) do
      [record] -> {:ok, Project.from_record(record)}
      [] -> {:error, :not_found}
    end
  end

  @doc "Find a project by its path."
  def get_by_path(path) do
    normalized = Path.expand(path)

    case :mnesia.dirty_index_read(:apothecary_projects, normalized, :path) do
      [record | _] -> {:ok, Project.from_record(record)}
      [] -> {:error, :not_found}
    end
  end

  @doc "Add an existing directory as a project."
  def add(path, opts \\ []) do
    normalized = Path.expand(path)

    case get_by_path(normalized) do
      {:ok, existing} ->
        {:error, {:already_exists, existing}}

      {:error, :not_found} ->
        create(normalized, opts)
    end
  end

  @doc "Create a new project record."
  def create(path, opts \\ []) do
    id = generate_id()
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    name = Keyword.get(opts, :name, Path.basename(path))
    type = Keyword.get_lazy(opts, :type, fn -> Project.detect_type(path) end)
    settings = Keyword.get(opts, :settings, %{}) |> seed_formula_defaults()

    record =
      {:apothecary_projects, id, name, path, :active,
       %{
         type: type,
         settings: settings,
         inserted_at: now,
         updated_at: now
       }}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} ->
        project = Project.from_record(record)
        broadcast({:project_added, project})
        {:ok, project}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Update a project."
  def update(id, changes) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_projects, id) do
          [record] ->
            updated = apply_changes(record, changes)
            :mnesia.write(updated)
            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        project = Project.from_record(record)
        broadcast({:project_updated, project})
        {:ok, project}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Archive a project (soft delete)."
  def archive(id) do
    update(id, %{status: :archived})
  end

  @doc "Reactivate an archived project."
  def activate(id) do
    update(id, %{status: :active})
  end

  @doc "Permanently delete a project record (does not delete files)."
  def delete(id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_projects, id) do
          [record] ->
            :mnesia.delete({:apothecary_projects, id})
            record

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        project = Project.from_record(record)
        broadcast({:project_deleted, project})
        {:ok, project}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Validate that a path is suitable as a project directory."
  def validate_path(path) do
    expanded = Path.expand(path)

    cond do
      not File.dir?(expanded) ->
        {:error, :not_a_directory}

      not git_repo?(expanded) ->
        {:error, :not_a_git_repo}

      true ->
        :ok
    end
  end

  defp git_repo?(path) do
    # Check for .git directory/file first (fast, no subprocess)
    File.exists?(Path.join(path, ".git")) or
      git_repo_via_cli?(path)
  end

  defp git_repo_via_cli?(path) do
    # Use -C flag instead of cd: option for more reliable path handling
    case Apothecary.CLI.run("git", ["-C", path, "rev-parse", "--is-inside-work-tree"]) do
      {:ok, output} -> String.trim(output) == "true"
      _ -> false
    end
  end

  defp apply_changes(record, changes) do
    {table, id, name, path, status, data} = record
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    name = Map.get(changes, :name, name)
    status = Map.get(changes, :status, status)

    data =
      data
      |> maybe_put(:type, changes[:type])
      |> maybe_put(:settings, changes[:settings])
      |> Map.put(:updated_at, now)

    {table, id, name, path, status, data}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # --- Formula Management ---

  @doc "Get formula definitions for a project."
  def get_formulas(project_id) do
    case get(project_id) do
      {:ok, project} ->
        formulas = project.settings[:formulas] || project.settings["formulas"] || %{}
        {:ok, formulas}

      error ->
        error
    end
  end

  @doc "Save a formula definition for a project."
  def put_formula(project_id, name, formula) when is_binary(name) and is_map(formula) do
    case get(project_id) do
      {:ok, project} ->
        formulas = project.settings[:formulas] || project.settings["formulas"] || %{}
        formulas = Map.put(formulas, name, formula)
        settings = Map.put(project.settings, :formulas, formulas)
        update(project_id, %{settings: settings})

      error ->
        error
    end
  end

  @doc "Delete a formula definition from a project."
  def delete_formula(project_id, name) do
    case get(project_id) do
      {:ok, project} ->
        formulas = project.settings[:formulas] || project.settings["formulas"] || %{}
        formulas = Map.delete(formulas, name)
        settings = Map.put(project.settings, :formulas, formulas)
        update(project_id, %{settings: settings})

      error ->
        error
    end
  end

  # Seed formula defaults into settings if not already present
  defp seed_formula_defaults(settings) do
    if Map.has_key?(settings, :formulas) || Map.has_key?(settings, "formulas") do
      settings
    else
      Map.put(settings, :formulas, Apothecary.Formula.defaults())
    end
  end

  defp generate_id do
    hex = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
    "proj-#{hex}"
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, message)
  end
end
