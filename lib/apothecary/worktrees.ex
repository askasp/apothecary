defmodule Apothecary.Worktrees do
  @moduledoc """
  BEAM-native task management backed by Mnesia.
  Replaces Poller + Beads with a single source of truth.

  Two-level model:
  - Worktree: unit of work/PR, dispatched to brewers
  - Task: step within a worktree, managed by brewers
  """

  use GenServer
  require Logger

  @pubsub Apothecary.PubSub
  @topic "worktrees:updates"
  @broadcast_debounce_ms 50

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  def force_refresh do
    GenServer.cast(__MODULE__, :broadcast)
  end

  # --- Dashboard-compatible API ---

  @doc "Get full state for dashboard mount (replaces Poller.get_state)."
  def get_state do
    worktrees = list_worktrees()
    tasks = list_all_tasks()
    all_items = worktrees ++ tasks
    ready = compute_ready_worktrees(worktrees)

    %{
      tasks: all_items,
      ready_tasks: ready,
      stats: compute_stats(all_items),
      last_poll: DateTime.utc_now(),
      error: nil
    }
  end

  @doc "Get state filtered by project_id."
  def get_state(project_id: project_id) do
    worktrees = list_worktrees(project_id: project_id)
    worktree_ids = MapSet.new(worktrees, & &1.id)

    tasks =
      list_all_tasks()
      |> Enum.filter(fn t -> MapSet.member?(worktree_ids, t.worktree_id) end)

    all_items = worktrees ++ tasks
    ready = compute_ready_worktrees(worktrees)

    %{
      tasks: all_items,
      ready_tasks: ready,
      stats: compute_stats(all_items),
      last_poll: DateTime.utc_now(),
      error: nil
    }
  end

  @doc "Look up any item by ID (worktree or task)."
  def show(id) do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      get_worktree(id)
    else
      case get_task(id) do
        {:ok, _} = ok -> ok
        {:error, :not_found} -> get_worktree(id)
      end
    end
  end

  @doc "Get children of an item. For worktrees, returns tasks. For tasks, returns []."
  def children(id) do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      {:ok, list_tasks(worktree_id: id)}
    else
      {:ok, []}
    end
  end

  @doc "Create a worktree or task based on attrs (uses :parent to decide)."
  def create(attrs) do
    if attrs[:parent] || attrs[:worktree_id] do
      worktree_id = attrs[:worktree_id] || attrs[:parent]
      create_task(Map.put(attrs, :worktree_id, worktree_id))
    else
      create_worktree(attrs)
    end
  end

  @doc "Claim an item (set to in_progress)."
  def claim(id) do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      update_worktree(id, %{status: "in_progress"})
    else
      update_task(id, %{status: "in_progress"})
    end
  end

  @doc "Close an item (set to done)."
  def close(id, reason \\ "Completed") do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      close_worktree(id, reason)
    else
      close_task(id, reason)
    end
  end

  @doc "Unclaim/requeue an item (set back to open, clear assignment)."
  def unclaim(id) do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      update_worktree(id, %{status: "open", assigned_brewer_id: nil})
    else
      update_task(id, %{status: "open"})
    end
  end

  @doc "Generic update — dispatches to worktree or task based on ID prefix."
  def update(id, changes) do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      update_worktree(id, changes)
    else
      update_task(id, changes)
    end
  end

  def update_title(id, title), do: update(id, %{title: title})
  def update_description(id, desc), do: update(id, %{description: desc})
  def update_priority(id, pri), do: update(id, %{priority: pri})
  def update_status(id, status), do: update(id, %{status: status})
  def update_notes(id, notes), do: add_note(id, notes)

  @doc "Requeue all orphaned items (in_progress but not actively worked)."
  def requeue_all_orphans(active_ids) do
    active_set = MapSet.new(active_ids, &to_string/1)
    all = list_worktrees() ++ list_all_tasks()

    orphans =
      Enum.filter(all, fn item ->
        item.status == "in_progress" and not MapSet.member?(active_set, to_string(item.id))
      end)

    Enum.each(orphans, &unclaim(&1.id))
    {:ok, length(orphans)}
  end

  @doc "Check if all tasks in a worktree are done."
  def all_tasks_done?(worktree_id) do
    tasks = list_tasks(worktree_id: worktree_id)
    tasks != [] and Enum.all?(tasks, &(&1.status == "done"))
  end

  @doc "Check if a worktree has any tasks."
  def has_tasks?(worktree_id) do
    list_tasks(worktree_id: worktree_id) != []
  end

  def stats do
    items = list_worktrees() ++ list_all_tasks()
    {:ok, compute_stats(items)}
  end

  @doc """
  Adopt an existing worktree from a filesystem path.

  Validates the path is a git repo, extracts the branch name, and checks if
  a worktree record already exists in Mnesia (matched by directory name as ID
  or by git_path). If found, returns the existing record. Otherwise creates
  a new worktree record pointing at the given path.

  Options:
  - project_id: associate with a project
  """
  def adopt_worktree(path, opts \\ []) do
    path = Path.expand(path)

    cond do
      not File.dir?(path) ->
        {:error, :not_a_directory}

      not Apothecary.Git.is_repo?(path) ->
        {:error, :not_a_git_repo}

      true ->
        dir_name = Path.basename(path)

        # Check if this worktree already exists in Mnesia by directory name (wt-* ID)
        existing =
          if String.starts_with?(dir_name, "wt-") do
            case get_worktree(dir_name) do
              {:ok, wt} -> wt
              _ -> nil
            end
          end

        # Also check by git_path match across all worktrees
        existing =
          existing ||
            Enum.find(list_worktrees(), fn wt ->
              wt.git_path && Path.expand(wt.git_path) == path
            end)

        if existing do
          {:ok, existing}
        else
          branch =
            case Apothecary.Git.current_branch(path) do
              {:ok, b} -> b
              _ -> nil
            end

          # Preserve the directory name as ID if it looks like a worktree ID
          id = if String.starts_with?(dir_name, "wt-"), do: dir_name, else: generate_id("wt")
          title = opts[:title] || dir_name
          now = DateTime.utc_now() |> DateTime.to_iso8601()

          record =
            {:apothecary_worktrees, id, opts[:project_id], "open", title, 3, path, branch, nil,
             nil,
             %{
               description: nil,
               notes: nil,
               pr_url: nil,
               mcp_servers: nil,
               kind: "task",
               pipeline: nil,
               pipeline_stage: 0,
               created_at: now,
               updated_at: now,
               blockers: [],
               dependents: []
             }}

          case :mnesia.transaction(fn -> :mnesia.write(record) end) do
            {:atomic, :ok} ->
              schedule_broadcast()
              {:ok, Apothecary.Worktree.from_record(record)}

            {:aborted, reason} ->
              {:error, reason}
          end
        end
    end
  end

  # --- Worktree Operations ---

  def create_worktree(attrs) do
    id = generate_id("wt")
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    record =
      {:apothecary_worktrees, id, attrs[:project_id], Map.get(attrs, :status, "open"),
       attrs[:title], Map.get(attrs, :priority, 3), attrs[:git_path], attrs[:git_branch],
       attrs[:parent_worktree_id], nil,
       %{
         description: attrs[:description],
         notes: nil,
         pr_url: nil,
         mcp_servers: attrs[:mcp_servers],
         kind: Map.get(attrs, :kind, "task"),
         parent_question_id: attrs[:parent_question_id],
         pipeline: resolve_pipeline(attrs[:pipeline], attrs[:project_id]),
         pipeline_stage: Map.get(attrs, :pipeline_stage, 0),
         created_at: now,
         updated_at: now,
         blockers: [],
         dependents: []
       }}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} ->
        schedule_broadcast()
        {:ok, Apothecary.Worktree.from_record(record)}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  def get_worktree(id) do
    case :mnesia.dirty_read(:apothecary_worktrees, id) do
      [record] -> {:ok, Apothecary.Worktree.from_record(record)}
      [] -> {:error, :not_found}
    end
  end

  def list_worktrees do
    :mnesia.dirty_match_object({:apothecary_worktrees, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
    |> Enum.map(&Apothecary.Worktree.from_record/1)
  end

  def list_worktrees(project_id: project_id) do
    :mnesia.dirty_match_object(
      {:apothecary_worktrees, :_, project_id, :_, :_, :_, :_, :_, :_, :_, :_}
    )
    |> Enum.map(&Apothecary.Worktree.from_record/1)
  end

  def update_worktree(id, changes) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_worktrees, id) do
          [record] ->
            updated = apply_worktree_changes(record, changes)
            :mnesia.write(updated)
            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        if Map.has_key?(changes, :status) do
          broadcast_immediately()
        else
          schedule_broadcast()
        end

        {:ok, Apothecary.Worktree.from_record(record)}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Atomically claim a worktree for a brewer (checks status + assignment)."
  def claim_worktree(id, brewer_id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.wread({:apothecary_worktrees, id}) do
          [record] ->
            status = elem(record, 3)
            current_brewer = elem(record, 9)

            if status in ["open", "revision_needed", "pr_open", "brew_done"] and
                 is_nil(current_brewer) do
              now = DateTime.utc_now() |> DateTime.to_iso8601()

              updated =
                record
                |> put_elem(3, "in_progress")
                |> put_elem(9, brewer_id)
                |> update_record_data(10, fn data -> Map.put(data, :updated_at, now) end)

              :mnesia.write(updated)
              updated
            else
              :mnesia.abort(:already_claimed)
            end

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        broadcast_immediately()
        {:ok, Apothecary.Worktree.from_record(record)}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  def release_worktree(id) do
    update_worktree(id, %{status: "open", assigned_brewer_id: nil})
  end

  def close_worktree(id, _reason \\ "Completed") do
    update_worktree(id, %{status: "done", assigned_brewer_id: nil})
  end

  def ready_worktrees do
    list_worktrees() |> compute_ready_worktrees()
  end

  def ready_worktrees(project_id: project_id) do
    list_worktrees(project_id: project_id) |> compute_ready_worktrees()
  end

  @doc "List worktrees with status pr_open."
  def pr_open_worktrees do
    list_worktrees() |> Enum.filter(&(&1.status == "pr_open"))
  end

  @doc "Mark a worktree as merged."
  def mark_merged(id) do
    update_worktree(id, %{status: "merged", assigned_brewer_id: nil})
  end

  @doc "Mark a worktree as needing revision (changes requested on PR)."
  def mark_revision_needed(id) do
    update_worktree(id, %{status: "revision_needed", assigned_brewer_id: nil})
  end

  @doc "Clean up a merged worktree from disk and set status to merged."
  def cleanup_merged_worktree(id) do
    # Update status FIRST so the card moves to "bottled" even if cleanup fails
    update_worktree(id, %{status: "merged", assigned_brewer_id: nil})

    # Best-effort cleanup — don't let failures leave status stuck in pr_open
    try do
      Apothecary.DevServer.stop_server(id)
    catch
      :exit, reason ->
        Logger.warning(
          "cleanup_merged_worktree: DevServer.stop_server failed for #{id}: #{inspect(reason)}"
        )
    end

    Apothecary.WorktreeManager.release(id)

    # Update local main so new worktrees branch from the latest code
    project_dir = resolve_project_dir(id)

    if project_dir do
      case Apothecary.Git.pull_main(project_dir) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("cleanup_merged_worktree: pull_main failed: #{inspect(reason)}")
      end
    end
  end

  @doc "Clean up a cancelled worktree (PR closed without merge) — release disk, set cancelled."
  def cleanup_cancelled_worktree(id) do
    update_worktree(id, %{status: "cancelled", assigned_brewer_id: nil})

    try do
      Apothecary.DevServer.stop_server(id)
    catch
      :exit, reason ->
        Logger.warning(
          "cleanup_cancelled_worktree: DevServer.stop_server failed for #{id}: #{inspect(reason)}"
        )
    end

    Apothecary.WorktreeManager.release(id)
  end

  # --- Task Operations ---

  def create_task(attrs) do
    id = generate_id("t")
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    record =
      {:apothecary_tasks, id, attrs[:worktree_id] || attrs[:parent],
       Map.get(attrs, :status, "open"), attrs[:title], Map.get(attrs, :priority, 3),
       %{
         description: attrs[:description],
         notes: nil,
         created_at: now,
         updated_at: now,
         blockers: attrs[:blockers] || [],
         dependents: []
       }}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} ->
        schedule_broadcast()
        {:ok, Apothecary.Task.from_record(record)}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  def get_task(id) do
    case :mnesia.dirty_read(:apothecary_tasks, id) do
      [record] -> {:ok, Apothecary.Task.from_record(record)}
      [] -> {:error, :not_found}
    end
  end

  def list_all_tasks do
    :mnesia.dirty_match_object({:apothecary_tasks, :_, :_, :_, :_, :_, :_})
    |> Enum.map(&Apothecary.Task.from_record/1)
  end

  def list_tasks(filters \\ []) do
    tasks = list_all_tasks()

    tasks
    |> maybe_filter(:worktree_id, filters[:worktree_id])
    |> maybe_filter(:status, filters[:status])
    |> Enum.sort_by(fn t -> {t.priority || 99, t.created_at || ""} end)
  end

  def update_task(id, changes) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_tasks, id) do
          [record] ->
            updated = apply_task_changes(record, changes)
            :mnesia.write(updated)
            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        if Map.has_key?(changes, :status) do
          broadcast_immediately()
        else
          schedule_broadcast()
        end

        {:ok, Apothecary.Task.from_record(record)}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Close a task and unblock dependents."
  def close_task(id, _reason \\ "Completed") do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_tasks, id) do
          [record] ->
            now = DateTime.utc_now() |> DateTime.to_iso8601()

            updated =
              record
              |> put_elem(3, "done")
              |> update_record_data(6, fn data -> Map.put(data, :updated_at, now) end)

            :mnesia.write(updated)

            # Unblock dependents
            data = elem(updated, 6)

            Enum.each(data[:dependents] || [], fn dep_id ->
              maybe_unblock_task(dep_id)
            end)

            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        # Broadcast immediately so the dashboard reflects completion in real-time,
        # rather than waiting for the debounced broadcast which can batch multiple
        # completions into a single update.
        broadcast_immediately()
        {:ok, Apothecary.Task.from_record(record)}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Add a note to a worktree or task."
  def add_note(id, note) do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      append_note(:apothecary_worktrees, id, 10, note, &Apothecary.Worktree.from_record/1)
    else
      append_note(:apothecary_tasks, id, 6, note, &Apothecary.Task.from_record/1)
    end
  end

  @doc "Add a dependency: blocked_id is blocked by blocker_id."
  def add_dependency(blocked_id, blocker_id) do
    blocked_id = to_string(blocked_id)
    blocker_id = to_string(blocker_id)

    # Reject self-dependencies
    if blocked_id == blocker_id do
      {:error, :self_dependency}
    else
      add_dependency_txn(blocked_id, blocker_id)
    end
  end

  defp add_dependency_txn(blocked_id, blocker_id) do
    result =
      :mnesia.transaction(fn ->
        # Check for cycles before adding
        if creates_cycle?(blocker_id, blocked_id, MapSet.new()) do
          :mnesia.abort(:cycle_detected)
        end

        # Add blocker to blocked's blockers list
        case :mnesia.read(:apothecary_tasks, blocked_id) do
          [blocked] ->
            blocked_data = elem(blocked, 6)
            blockers = Enum.uniq([blocker_id | blocked_data[:blockers] || []])

            blocked =
              update_record_data(blocked, 6, fn data -> Map.put(data, :blockers, blockers) end)

            # If blocker is not done, set blocked to "blocked"
            blocked =
              case :mnesia.read(:apothecary_tasks, to_string(blocker_id)) do
                [blocker_rec] ->
                  if elem(blocker_rec, 3) != "done",
                    do: put_elem(blocked, 3, "blocked"),
                    else: blocked

                [] ->
                  blocked
              end

            :mnesia.write(blocked)

          [] ->
            :mnesia.abort(:not_found)
        end

        # Add blocked to blocker's dependents list
        case :mnesia.read(:apothecary_tasks, to_string(blocker_id)) do
          [blocker] ->
            blocker_data = elem(blocker, 6)
            dependents = Enum.uniq([to_string(blocked_id) | blocker_data[:dependents] || []])

            blocker =
              update_record_data(blocker, 6, fn data -> Map.put(data, :dependents, dependents) end)

            :mnesia.write(blocker)

          [] ->
            :ok
        end
      end)

    case result do
      {:atomic, _} ->
        schedule_broadcast()
        {:ok, :added}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  # Walk from `current_id` following blocker chains to see if we reach `target_id`.
  # If so, adding target_id -> current_id would create a cycle.
  # Must be called inside a Mnesia transaction.
  defp creates_cycle?(current_id, target_id, visited) do
    if current_id == target_id do
      true
    else
      if MapSet.member?(visited, current_id) do
        false
      else
        visited = MapSet.put(visited, current_id)

        case :mnesia.read(:apothecary_tasks, current_id) do
          [record] ->
            data = elem(record, 6)
            dependents = data[:dependents] || []
            Enum.any?(dependents, fn dep_id -> creates_cycle?(dep_id, target_id, visited) end)

          [] ->
            false
        end
      end
    end
  end

  @doc "Remove a dependency: blocked_id is no longer blocked by blocker_id."
  def remove_dependency(blocked_id, blocker_id) do
    result =
      :mnesia.transaction(fn ->
        blocked_id = to_string(blocked_id)
        blocker_id = to_string(blocker_id)

        # Remove blocker from blocked's blockers list
        case :mnesia.read(:apothecary_tasks, blocked_id) do
          [blocked] ->
            blocked_data = elem(blocked, 6)
            blockers = List.delete(blocked_data[:blockers] || [], blocker_id)

            blocked =
              update_record_data(blocked, 6, fn data -> Map.put(data, :blockers, blockers) end)

            # Check if all remaining blockers are done
            all_done =
              Enum.all?(blockers, fn bid ->
                case :mnesia.read(:apothecary_tasks, bid) do
                  [rec] -> elem(rec, 3) == "done"
                  _ -> false
                end
              end)

            blocked =
              if all_done and elem(blocked, 3) == "blocked",
                do: put_elem(blocked, 3, "open"),
                else: blocked

            :mnesia.write(blocked)

          [] ->
            :ok
        end

        # Remove blocked from blocker's dependents list
        case :mnesia.read(:apothecary_tasks, blocker_id) do
          [blocker] ->
            blocker_data = elem(blocker, 6)
            dependents = List.delete(blocker_data[:dependents] || [], blocked_id)

            blocker =
              update_record_data(blocker, 6, fn data -> Map.put(data, :dependents, dependents) end)

            :mnesia.write(blocker)

          [] ->
            :ok
        end
      end)

    case result do
      {:atomic, _} ->
        schedule_broadcast()
        {:ok, :removed}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  # --- Recipe Operations ---

  @recipe_topic "recipes:updates"

  def subscribe_recipes do
    Phoenix.PubSub.subscribe(@pubsub, @recipe_topic)
  end

  def create_recipe(attrs) do
    id = generate_id("recipe")
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    schedule = attrs[:schedule] || attrs["schedule"]

    case Crontab.CronExpression.Parser.parse(schedule) do
      {:ok, _cron} ->
        record =
          {:apothecary_recipes, id, attrs[:title], attrs[:description], schedule,
           Map.get(attrs, :enabled, true), Map.get(attrs, :priority, 3),
           %{
             last_run_at: nil,
             next_run_at: nil,
             created_at: now,
             updated_at: now,
             notes: nil
           }}

        case :mnesia.transaction(fn -> :mnesia.write(record) end) do
          {:atomic, :ok} ->
            recipe = Apothecary.Recipe.from_record(record)
            broadcast_recipe_change({:recipe_created, recipe})
            {:ok, recipe}

          {:aborted, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:invalid_schedule, reason}}
    end
  end

  def get_recipe(id) do
    case :mnesia.dirty_read(:apothecary_recipes, id) do
      [record] -> {:ok, Apothecary.Recipe.from_record(record)}
      [] -> {:error, :not_found}
    end
  end

  def list_recipes(filters \\ []) do
    recipes =
      :mnesia.dirty_match_object({:apothecary_recipes, :_, :_, :_, :_, :_, :_, :_})
      |> Enum.map(&Apothecary.Recipe.from_record/1)

    case filters[:enabled] do
      nil -> recipes
      val -> Enum.filter(recipes, &(&1.enabled == val))
    end
  end

  def update_recipe(id, changes) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_recipes, id) do
          [record] ->
            updated = apply_recipe_changes(record, changes)
            :mnesia.write(updated)
            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        recipe = Apothecary.Recipe.from_record(record)
        broadcast_recipe_change({:recipe_updated, recipe})
        {:ok, recipe}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  def delete_recipe(id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_recipes, id) do
          [record] ->
            :mnesia.delete({:apothecary_recipes, id})
            record

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        recipe = Apothecary.Recipe.from_record(record)
        broadcast_recipe_change({:recipe_deleted, recipe})
        {:ok, recipe}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  def toggle_recipe(id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_recipes, id) do
          [record] ->
            updated = put_elem(record, 5, !elem(record, 5))
            now = DateTime.utc_now() |> DateTime.to_iso8601()

            updated =
              update_record_data(updated, 7, fn data -> Map.put(data, :updated_at, now) end)

            :mnesia.write(updated)
            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        recipe = Apothecary.Recipe.from_record(record)
        broadcast_recipe_change({:recipe_toggled, recipe})
        {:ok, recipe}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Update last_run_at and next_run_at for a recipe (called by BrewScheduler)."
  def mark_recipe_run(id, next_run_at) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_recipes, id) do
          [record] ->
            updated =
              update_record_data(record, 7, fn data ->
                data
                |> Map.put(:last_run_at, now)
                |> Map.put(:next_run_at, next_run_at)
                |> Map.put(:updated_at, now)
              end)

            :mnesia.write(updated)
            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        recipe = Apothecary.Recipe.from_record(record)
        broadcast_recipe_change({:recipe_updated, recipe})
        {:ok, recipe}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp apply_recipe_changes(record, changes) do
    {table, id, title, description, schedule, enabled, priority, data} = record
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    title = Map.get(changes, :title, title)
    description = Map.get(changes, :description, description)
    priority = Map.get(changes, :priority, priority)

    enabled =
      if Map.has_key?(changes, :enabled), do: changes.enabled, else: enabled

    schedule =
      if Map.has_key?(changes, :schedule), do: changes.schedule, else: schedule

    data = Map.put(data, :updated_at, now)

    {table, id, title, description, schedule, enabled, priority, data}
  end

  defp broadcast_recipe_change(message) do
    Phoenix.PubSub.broadcast(@pubsub, @recipe_topic, message)
  end

  @doc "Delete a task, cleaning up dependency references from other tasks."
  def delete_task(id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_tasks, id) do
          [record] ->
            data = elem(record, 6)

            # Remove this task from blockers lists of its dependents
            Enum.each(data[:dependents] || [], fn dep_id ->
              case :mnesia.read(:apothecary_tasks, dep_id) do
                [dep] ->
                  dep_data = elem(dep, 6)
                  blockers = List.delete(dep_data[:blockers] || [], id)

                  dep =
                    update_record_data(dep, 6, fn d -> Map.put(d, :blockers, blockers) end)

                  # Unblock if no remaining undone blockers
                  dep =
                    if elem(dep, 3) == "blocked" do
                      all_done =
                        Enum.all?(blockers, fn bid ->
                          case :mnesia.read(:apothecary_tasks, bid) do
                            [rec] -> elem(rec, 3) == "done"
                            _ -> false
                          end
                        end)

                      if all_done, do: put_elem(dep, 3, "open"), else: dep
                    else
                      dep
                    end

                  :mnesia.write(dep)

                [] ->
                  :ok
              end
            end)

            # Remove this task from dependents lists of its blockers
            Enum.each(data[:blockers] || [], fn blocker_id ->
              case :mnesia.read(:apothecary_tasks, blocker_id) do
                [blocker] ->
                  blocker_data = elem(blocker, 6)
                  dependents = List.delete(blocker_data[:dependents] || [], id)

                  blocker =
                    update_record_data(blocker, 6, fn d -> Map.put(d, :dependents, dependents) end)

                  :mnesia.write(blocker)

                [] ->
                  :ok
              end
            end)

            :mnesia.delete({:apothecary_tasks, id})
            record

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        broadcast_immediately()
        {:ok, Apothecary.Task.from_record(record)}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  def ready_tasks(worktree_id) do
    tasks = list_tasks(worktree_id: worktree_id)
    task_status_map = Map.new(tasks, fn t -> {t.id, t.status} end)
    Enum.filter(tasks, &task_ready?(&1, task_status_map))
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    # Recover orphaned worktrees after brewers have had time to start
    Process.send_after(self(), :recover_orphans, 10_000)
    {:ok, %{broadcast_timer: nil}}
  end

  @impl true
  def handle_info(:recover_orphans, state) do
    # Only requeue worktrees whose assigned brewer isn't actually running
    active_brewer_ids = get_active_brewer_ids()

    case requeue_all_orphans(active_brewer_ids) do
      {:ok, 0} -> :ok
      {:ok, count} -> Logger.info("Recovered #{count} orphaned worktree(s) on startup")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:do_broadcast, state) do
    task_state = get_state()
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:worktrees_update, task_state})
    {:noreply, %{state | broadcast_timer: nil}}
  end

  @impl true
  def handle_cast(:broadcast, state) do
    state = schedule_broadcast_timer(state)
    {:noreply, state}
  end

  # --- Private: Broadcast ---

  defp schedule_broadcast do
    GenServer.cast(__MODULE__, :broadcast)
  end

  # Bypass debounce — broadcast state immediately from the calling process.
  # Used for status changes (e.g. task completion) so the dashboard
  # reflects progress in real-time instead of batching updates.
  defp broadcast_immediately do
    task_state = get_state()
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:worktrees_update, task_state})
  end

  # Leading-edge debounce: fires on the FIRST change in a window, then ignores
  # subsequent changes until the timer fires. This prevents the trailing-edge
  # problem where rapid changes keep pushing the broadcast further into the future.
  defp schedule_broadcast_timer(state) do
    if state.broadcast_timer do
      # Timer already pending — don't reset it (leading-edge behavior)
      state
    else
      timer = Process.send_after(self(), :do_broadcast, @broadcast_debounce_ms)
      %{state | broadcast_timer: timer}
    end
  end

  # --- Private: ID Generation ---

  defp generate_id(prefix) do
    hex = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
    "#{prefix}-#{hex}"
  end

  # --- Private: Ready Computation ---

  defp compute_ready_worktrees(worktrees) do
    # Pre-fetch all worktrees into a status map for O(1) lookups
    wt_status_map = Map.new(worktrees, fn wt -> {wt.id, wt.status} end)

    worktrees
    |> Enum.filter(&worktree_ready?(&1, wt_status_map))
    |> Enum.sort_by(fn wt -> {wt.priority || 99, wt.created_at || ""} end)
  end

  defp worktree_ready?(
         %{status: status, assigned_brewer_id: nil, parent_worktree_id: nil, id: id},
         _map
       )
       when status in ["open", "revision_needed"] do
    # Only dispatch if worktree has at least one task
    list_tasks(worktree_id: id) != []
  end

  defp worktree_ready?(
         %{status: status, assigned_brewer_id: nil, parent_worktree_id: pid, id: id},
         wt_status_map
       )
       when status in ["open", "revision_needed"] and not is_nil(pid) do
    Map.get(wt_status_map, pid) in ["done", "merged"] and
      list_tasks(worktree_id: id) != []
  end

  # PR is open or brew is done but new tasks were added — redispatch to work on them
  defp worktree_ready?(%{status: status, assigned_brewer_id: nil, id: id}, _map)
       when status in ["pr_open", "brew_done"] do
    list_tasks(worktree_id: id, status: "open") |> Enum.any?()
  end

  defp worktree_ready?(_, _map), do: false

  defp task_ready?(%{status: "open", blockers: []}, _task_status_map), do: true

  defp task_ready?(%{status: "open", blockers: blockers}, task_status_map) do
    Enum.all?(blockers, fn blocker_id ->
      Map.get(task_status_map, blocker_id) == "done"
    end)
  end

  defp task_ready?(_, _task_status_map), do: false

  # --- Private: Stats ---

  defp compute_stats(items) do
    by_status = Enum.group_by(items, & &1.status)

    %{
      "total" => length(items),
      "open" => length(by_status["open"] || []),
      "in_progress" => length(by_status["in_progress"] || []),
      "done" => length(by_status["done"] || []),
      "blocked" => length(by_status["blocked"] || []),
      "merge_conflict" => length(by_status["merge_conflict"] || []),
      "pr_open" => length(by_status["pr_open"] || []),
      "revision_needed" => length(by_status["revision_needed"] || []),
      "merged" => length(by_status["merged"] || [])
    }
  end

  # --- Private: Record Manipulation ---

  defp apply_worktree_changes(record, changes) do
    {table, id, project_id, status, title, priority, git_path, git_branch, parent_worktree_id,
     assigned_brewer_id, data} = record

    now = DateTime.utc_now() |> DateTime.to_iso8601()

    status = Map.get(changes, :status, status)
    title = Map.get(changes, :title, title)
    priority = Map.get(changes, :priority, priority)
    git_path = Map.get(changes, :git_path, git_path)
    git_branch = Map.get(changes, :git_branch, git_branch)
    parent_worktree_id = Map.get(changes, :parent_worktree_id, parent_worktree_id)

    assigned_brewer_id =
      if Map.has_key?(changes, :assigned_brewer_id),
        do: changes.assigned_brewer_id,
        else: assigned_brewer_id

    data =
      data
      |> maybe_put(:description, changes[:description])
      |> maybe_put(:notes, changes[:notes])
      |> maybe_put(:pr_url, changes[:pr_url])
      |> maybe_put(:mcp_servers, changes[:mcp_servers])
      |> maybe_put(:blockers, changes[:blockers])
      |> maybe_put(:dependents, changes[:dependents])
      |> maybe_put(:pipeline, changes[:pipeline])
      |> maybe_put(:pipeline_stage, changes[:pipeline_stage])
      |> Map.put(:updated_at, now)

    {table, id, project_id, status, title, priority, git_path, git_branch, parent_worktree_id,
     assigned_brewer_id, data}
  end

  defp apply_task_changes(record, changes) do
    {table, id, worktree_id, status, title, priority, data} = record
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    worktree_id = Map.get(changes, :worktree_id, worktree_id)
    status = Map.get(changes, :status, status)
    title = Map.get(changes, :title, title)
    priority = Map.get(changes, :priority, priority)

    data =
      data
      |> maybe_put(:description, changes[:description])
      |> maybe_put(:notes, changes[:notes])
      |> maybe_put(:blockers, changes[:blockers])
      |> maybe_put(:dependents, changes[:dependents])
      |> Map.put(:updated_at, now)

    {table, id, worktree_id, status, title, priority, data}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp update_record_data(record, index, fun) do
    data = elem(record, index)
    put_elem(record, index, fun.(data))
  end

  defp maybe_unblock_task(task_id) do
    case :mnesia.read(:apothecary_tasks, task_id) do
      [record] ->
        if elem(record, 3) == "blocked" do
          data = elem(record, 6)
          blockers = data[:blockers] || []

          all_done =
            Enum.all?(blockers, fn bid ->
              case :mnesia.read(:apothecary_tasks, bid) do
                [rec] -> elem(rec, 3) == "done"
                _ -> false
              end
            end)

          if all_done do
            :mnesia.write(put_elem(record, 3, "open"))
          end
        end

      [] ->
        :ok
    end
  end

  defp append_note(table, id, data_index, note, from_record_fn) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(table, id) do
          [record] ->
            now = DateTime.utc_now() |> DateTime.to_iso8601()
            timestamp = Calendar.strftime(DateTime.utc_now(), "[%Y-%m-%d %H:%M:%S]")
            data = elem(record, data_index)
            existing = data[:notes] || ""
            timestamped_note = "#{timestamp} #{note}"

            new_notes =
              if existing == "", do: timestamped_note, else: "#{existing}\n#{timestamped_note}"

            updated =
              put_elem(
                record,
                data_index,
                Map.merge(data, %{notes: new_notes, updated_at: now})
              )

            :mnesia.write(updated)
            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        schedule_broadcast()
        {:ok, from_record_fn.(record)}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp get_active_brewer_ids do
    try do
      status = Apothecary.Dispatcher.status()

      status.agents
      |> Map.values()
      |> Enum.flat_map(fn agent ->
        if agent.current_worktree, do: [agent.current_worktree.id], else: []
      end)
    rescue
      _ -> []
    catch
      :exit, _ -> []
    end
  end

  # --- Private: Filtering ---

  defp resolve_project_dir(worktree_id) do
    case get_worktree(worktree_id) do
      {:ok, %{project_id: project_id}} when not is_nil(project_id) ->
        case Apothecary.Projects.get(project_id) do
          {:ok, project} -> project.path
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp maybe_filter(items, _field, nil), do: items

  defp maybe_filter(items, field, value) do
    value = to_string(value)
    Enum.filter(items, fn item -> to_string(Map.get(item, field)) == value end)
  end

  # --- Private: Pipeline Resolution ---

  @doc false
  # Resolve a pipeline value: can be a list of stages (pass-through),
  # a string name (looked up from project settings), or nil (use project default).
  defp resolve_pipeline(nil, nil), do: nil

  defp resolve_pipeline(nil, project_id) do
    # Inherit project default pipeline
    case get_project_pipelines(project_id) do
      {_pipelines, default_name} when is_binary(default_name) ->
        resolve_pipeline(default_name, project_id)

      _ ->
        nil
    end
  end

  defp resolve_pipeline(stages, _project_id) when is_list(stages), do: stages

  defp resolve_pipeline(name, project_id) when is_binary(name) do
    case get_project_pipelines(project_id) do
      {pipelines, _default} when is_map(pipelines) ->
        case Map.get(pipelines, name) do
          stages when is_list(stages) -> stages
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp resolve_pipeline(_, _), do: nil

  @doc "Get pipeline definitions and default from a project's settings."
  def get_project_pipelines(nil), do: {%{}, nil}

  def get_project_pipelines(project_id) do
    case Apothecary.Projects.get(project_id) do
      {:ok, project} ->
        pipelines = project.settings[:pipelines] || project.settings["pipelines"] || %{}
        default = project.settings[:default_pipeline] || project.settings["default_pipeline"]
        {pipelines, default}

      _ ->
        {%{}, nil}
    end
  end

  @doc "Check if a worktree has remaining pipeline stages."
  def pipeline_has_next_stage?(%{pipeline: stages, pipeline_stage: current})
      when is_list(stages) and length(stages) > current + 1,
      do: true

  def pipeline_has_next_stage?(_), do: false

  @doc "Get the current pipeline stage definition for a worktree."
  def current_pipeline_stage(%{pipeline: stages, pipeline_stage: idx})
      when is_list(stages) do
    Enum.at(stages, idx)
  end

  def current_pipeline_stage(_), do: nil

  @doc "Advance a worktree to its next pipeline stage. Creates a task for the next stage and resets the worktree for redispatch."
  def advance_pipeline(worktree_id) do
    case get_worktree(worktree_id) do
      {:ok, %{pipeline: stages, pipeline_stage: current}}
      when is_list(stages) and length(stages) > current + 1 ->
        next_idx = current + 1
        next_stage = Enum.at(stages, next_idx)

        stage_name = next_stage["name"] || next_stage[:name] || "Stage #{next_idx + 1}"
        stage_prompt = next_stage["prompt"] || next_stage[:prompt]
        stage_kind = next_stage["kind"] || next_stage[:kind] || "task"

        # Create task for the next stage
        create_task(%{
          worktree_id: worktree_id,
          title: "[pipeline] #{stage_name}",
          description: stage_prompt || stage_name,
          priority: 0
        })

        # Advance stage counter and reset for redispatch to a fresh brewer
        update_worktree(worktree_id, %{
          pipeline_stage: next_idx,
          status: "open",
          assigned_brewer_id: nil
        })

        add_note(
          worktree_id,
          "Pipeline advancing: stage #{current + 1}/#{length(stages)} (#{stage_name}) → dispatching fresh brewer"
        )

        Logger.info(
          "Pipeline advanced for #{worktree_id}: stage #{next_idx + 1}/#{length(stages)} (#{stage_name}, kind: #{stage_kind})"
        )

        {:advanced, %{stage: next_idx, name: stage_name, kind: stage_kind}}

      _ ->
        :complete
    end
  end
end
