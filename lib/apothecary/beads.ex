defmodule Apothecary.Beads do
  @moduledoc "Interface to the Beads (bd) CLI tool."

  alias Apothecary.{Bead, CLI}

  defp bd_path, do: Application.get_env(:apothecary, :bd_path, "bd")
  defp project_dir, do: Application.get_env(:apothecary, :project_dir)

  @doc "Initialize beads in the project directory (idempotent)."
  def init do
    CLI.run(bd_path(), ["init", "--quiet"], cd: project_dir())
  end

  @doc "List all tasks."
  def list do
    case CLI.run(bd_path(), ["list", "--json"], cd: project_dir()) do
      {:ok, json} -> {:ok, parse_beads(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "List tasks that are ready (no open blockers)."
  def ready do
    case CLI.run(bd_path(), ["ready", "--json"], cd: project_dir()) do
      {:ok, json} -> {:ok, parse_beads(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Show a single task by ID."
  def show(id) do
    case CLI.run(bd_path(), ["show", to_string(id), "--json"], cd: project_dir()) do
      {:ok, json} -> {:ok, parse_bead(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Get project statistics."
  def stats do
    case CLI.run(bd_path(), ["stats", "--json"], cd: project_dir()) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:ok, %{}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get the dependency tree for a task (text output)."
  def dep_tree(id) do
    CLI.run(bd_path(), ["dep", "tree", to_string(id)], cd: project_dir())
  end

  @doc "Claim a task for this agent."
  def claim(id) do
    CLI.run(bd_path(), ["update", to_string(id), "--claim"], cd: project_dir())
  end

  @doc "Close a completed task."
  def close(id, reason \\ "Completed") do
    CLI.run(bd_path(), ["close", to_string(id), "--reason", reason], cd: project_dir())
  end

  @doc "Create a new task."
  def create(attrs) do
    args =
      ["create", attrs.title] ++
        if(attrs[:type], do: ["-t", to_string(attrs.type)], else: []) ++
        if(attrs[:priority], do: ["-p", to_string(attrs.priority)], else: []) ++
        if(attrs[:parent], do: ["--parent", to_string(attrs.parent)], else: []) ++
        if(attrs[:description], do: ["-d", attrs.description], else: []) ++
        ["--json"]

    case CLI.run(bd_path(), args, cd: project_dir()) do
      {:ok, json} -> {:ok, parse_bead(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Update notes on a task."
  def update_notes(id, notes) do
    CLI.run(bd_path(), ["update", to_string(id), "--notes", notes], cd: project_dir())
  end

  @doc "Add a dependency: blocked_id is blocked by blocker_id."
  def dep_add(blocked_id, blocker_id) do
    CLI.run(
      bd_path(),
      ["dep", "add", to_string(blocked_id), to_string(blocker_id)],
      cd: project_dir()
    )
  end

  defp parse_beads(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) -> Enum.map(list, &Bead.from_map/1)
      {:ok, _} -> []
      {:error, _} -> []
    end
  end

  defp parse_bead(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> Bead.from_map(map)
      {:error, _} -> nil
    end
  end
end
