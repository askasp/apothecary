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
    settings = Keyword.get(opts, :settings, %{}) |> seed_pipeline_defaults()

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

  # --- Pipeline Management ---

  @doc "Get pipeline definitions for a project."
  def get_pipelines(project_id) do
    case get(project_id) do
      {:ok, project} ->
        pipelines = project.settings[:pipelines] || project.settings["pipelines"] || %{}
        default = project.settings[:default_pipeline] || project.settings["default_pipeline"]
        {:ok, %{pipelines: pipelines, default: default}}

      error ->
        error
    end
  end

  @doc "Save a pipeline definition for a project."
  def put_pipeline(project_id, name, stages) when is_binary(name) and is_list(stages) do
    case get(project_id) do
      {:ok, project} ->
        pipelines = project.settings[:pipelines] || project.settings["pipelines"] || %{}
        pipelines = Map.put(pipelines, name, stages)
        settings = Map.put(project.settings, :pipelines, pipelines)
        update(project_id, %{settings: settings})

      error ->
        error
    end
  end

  @doc "Delete a pipeline definition from a project."
  def delete_pipeline(project_id, name) do
    case get(project_id) do
      {:ok, project} ->
        pipelines = project.settings[:pipelines] || project.settings["pipelines"] || %{}
        pipelines = Map.delete(pipelines, name)

        settings =
          project.settings
          |> Map.put(:pipelines, pipelines)
          |> maybe_clear_default(name)

        update(project_id, %{settings: settings})

      error ->
        error
    end
  end

  @doc "Set the default pipeline for a project."
  def set_default_pipeline(project_id, name) do
    case get(project_id) do
      {:ok, project} ->
        settings = Map.put(project.settings, :default_pipeline, name)
        update(project_id, %{settings: settings})

      error ->
        error
    end
  end

  @doc "Get the default pipeline stages for a project. Returns a list or nil."
  def default_pipeline_stages(project_id) do
    case get_pipelines(project_id) do
      {:ok, %{pipelines: pipelines, default: name}} when is_binary(name) ->
        Map.get(pipelines, name)

      _ ->
        nil
    end
  end

  @doc "Default pipeline definitions seeded on new projects."
  def default_pipelines do
    %{
      "standard" => [
        %{name: "implement", kind: "task"},
        %{name: "self-review", kind: "review",
          prompt: "Review all changes on this branch against main. Check for:\n" <>
            "- Unused variables, imports, or dead code\n" <>
            "- Missing error handling at system boundaries\n" <>
            "- Inconsistent naming or style\n" <>
            "- Hardcoded values that should be configurable\n" <>
            "- Security issues (injection, XSS, etc.)\n" <>
            "- Overly complex code that could be simplified\n\n" <>
            "Fix any issues you find directly. If everything looks good, add a note saying so."}
      ],
      "thorough" => [
        %{name: "implement", kind: "task"},
        %{name: "self-review", kind: "review",
          prompt: "Review all changes on this branch against main. Fix any code quality issues, " <>
            "unused code, naming inconsistencies, or missing error handling."},
        %{name: "test", kind: "task",
          prompt: "Run the full test suite. Fix any failures. If tests are missing for new " <>
            "functionality, add them."}
      ]
    }
  end

  # Seed pipeline defaults into settings if not already present
  defp seed_pipeline_defaults(settings) do
    if Map.has_key?(settings, :pipelines) || Map.has_key?(settings, "pipelines") do
      settings
    else
      settings
      |> Map.put(:pipelines, default_pipelines())
      |> Map.put(:default_pipeline, nil)
    end
  end

  defp maybe_clear_default(settings, deleted_name) do
    current = settings[:default_pipeline] || settings["default_pipeline"]
    if current == deleted_name, do: Map.put(settings, :default_pipeline, nil), else: settings
  end

  defp generate_id do
    hex = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
    "proj-#{hex}"
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, message)
  end
end
