defmodule Apothecary.Ingredients do
  @moduledoc """
  BEAM-native task management backed by Mnesia.
  Replaces Poller + Beads with a single source of truth.

  Two-level model:
  - Concoction: unit of work/PR, dispatched to brewers
  - Ingredient: step within a concoction, managed by brewers
  """

  use GenServer
  require Logger

  @pubsub Apothecary.PubSub
  @topic "ingredients:updates"
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
    concoctions = list_concoctions()
    ingredients = list_all_ingredients()
    all_items = concoctions ++ ingredients
    ready = compute_ready_concoctions(concoctions)

    %{
      tasks: all_items,
      ready_tasks: ready,
      stats: compute_stats(all_items),
      last_poll: DateTime.utc_now(),
      error: nil
    }
  end

  @doc "Look up any item by ID (concoction or ingredient)."
  def show(id) do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      get_concoction(id)
    else
      case get_ingredient(id) do
        {:ok, _} = ok -> ok
        {:error, :not_found} -> get_concoction(id)
      end
    end
  end

  @doc "Get children of an item. For concoctions, returns ingredients. For ingredients, returns []."
  def children(id) do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      {:ok, list_ingredients(concoction_id: id)}
    else
      {:ok, []}
    end
  end

  @doc "Create a concoction or ingredient based on attrs (uses :parent to decide)."
  def create(attrs) do
    if attrs[:parent] || attrs[:concoction_id] do
      concoction_id = attrs[:concoction_id] || attrs[:parent]
      create_ingredient(Map.put(attrs, :concoction_id, concoction_id))
    else
      create_concoction(attrs)
    end
  end

  @doc "Claim an item (set to in_progress)."
  def claim(id) do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      update_concoction(id, %{status: "in_progress"})
    else
      update_ingredient(id, %{status: "in_progress"})
    end
  end

  @doc "Close an item (set to done)."
  def close(id, reason \\ "Completed") do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      close_concoction(id, reason)
    else
      close_ingredient(id, reason)
    end
  end

  @doc "Unclaim/requeue an item (set back to open, clear assignment)."
  def unclaim(id) do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      update_concoction(id, %{status: "open", assigned_brewer_id: nil})
    else
      update_ingredient(id, %{status: "open"})
    end
  end

  @doc "Generic update — dispatches to concoction or ingredient based on ID prefix."
  def update(id, changes) do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      update_concoction(id, changes)
    else
      update_ingredient(id, changes)
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
    all = list_concoctions() ++ list_all_ingredients()

    orphans =
      Enum.filter(all, fn item ->
        item.status == "in_progress" and not MapSet.member?(active_set, to_string(item.id))
      end)

    Enum.each(orphans, &unclaim(&1.id))
    {:ok, length(orphans)}
  end

  @doc "Check if all ingredients in a concoction are done."
  def all_ingredients_done?(concoction_id) do
    ingredients = list_ingredients(concoction_id: concoction_id)
    ingredients != [] and Enum.all?(ingredients, &(&1.status == "done"))
  end

  @doc "Check if a concoction has any ingredients."
  def has_ingredients?(concoction_id) do
    list_ingredients(concoction_id: concoction_id) != []
  end

  def stats do
    items = list_concoctions() ++ list_all_ingredients()
    {:ok, compute_stats(items)}
  end

  # --- Concoction Operations ---

  def create_concoction(attrs) do
    id = generate_id("wt")
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    record =
      {:apothecary_concoctions, id, Map.get(attrs, :status, "open"), attrs[:title],
       Map.get(attrs, :priority, 3), attrs[:git_path], attrs[:git_branch],
       attrs[:parent_concoction_id], nil,
       %{
         description: attrs[:description],
         notes: nil,
         pr_url: nil,
         created_at: now,
         updated_at: now,
         blockers: [],
         dependents: []
       }}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} ->
        schedule_broadcast()
        {:ok, Apothecary.Concoction.from_record(record)}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  def get_concoction(id) do
    case :mnesia.dirty_read(:apothecary_concoctions, id) do
      [record] -> {:ok, Apothecary.Concoction.from_record(record)}
      [] -> {:error, :not_found}
    end
  end

  def list_concoctions do
    :mnesia.dirty_match_object({:apothecary_concoctions, :_, :_, :_, :_, :_, :_, :_, :_, :_})
    |> Enum.map(&Apothecary.Concoction.from_record/1)
  end

  def update_concoction(id, changes) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_concoctions, id) do
          [record] ->
            updated = apply_concoction_changes(record, changes)
            :mnesia.write(updated)
            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        schedule_broadcast()
        {:ok, Apothecary.Concoction.from_record(record)}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Atomically claim a concoction for a brewer (checks status + assignment)."
  def claim_concoction(id, brewer_id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.wread({:apothecary_concoctions, id}) do
          [record] ->
            status = elem(record, 2)
            current_brewer = elem(record, 8)

            if status in ["open", "revision_needed", "pr_open"] and is_nil(current_brewer) do
              now = DateTime.utc_now() |> DateTime.to_iso8601()

              updated =
                record
                |> put_elem(2, "in_progress")
                |> put_elem(8, brewer_id)
                |> update_record_data(9, fn data -> Map.put(data, :updated_at, now) end)

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
        schedule_broadcast()
        {:ok, Apothecary.Concoction.from_record(record)}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  def release_concoction(id) do
    update_concoction(id, %{status: "open", assigned_brewer_id: nil})
  end

  def close_concoction(id, _reason \\ "Completed") do
    update_concoction(id, %{status: "done", assigned_brewer_id: nil})
  end

  def ready_concoctions do
    list_concoctions() |> compute_ready_concoctions()
  end

  @doc "List concoctions with status pr_open."
  def pr_open_concoctions do
    list_concoctions() |> Enum.filter(&(&1.status == "pr_open"))
  end

  @doc "Mark a concoction as merged."
  def mark_merged(id) do
    update_concoction(id, %{status: "merged", assigned_brewer_id: nil})
  end

  @doc "Mark a concoction as needing revision (changes requested on PR)."
  def mark_revision_needed(id) do
    update_concoction(id, %{status: "revision_needed", assigned_brewer_id: nil})
  end

  @doc "Clean up a merged concoction from disk and set status to done."
  def cleanup_merged_concoction(id) do
    # Update status FIRST so the card moves to "bottled" even if cleanup fails
    update_concoction(id, %{status: "done", assigned_brewer_id: nil})

    # Best-effort cleanup — don't let failures leave status stuck in pr_open
    try do
      Apothecary.DevServer.stop_server(id)
    catch
      :exit, reason ->
        Logger.warning(
          "cleanup_merged_concoction: DevServer.stop_server failed for #{id}: #{inspect(reason)}"
        )
    end

    Apothecary.WorktreeManager.release(id)

    # Update local main so new worktrees branch from the latest code
    case Apothecary.Git.pull_main() do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("cleanup_merged_concoction: pull_main failed: #{inspect(reason)}")
    end
  end

  @doc "Clean up a cancelled concoction (PR closed without merge) — release disk, set cancelled."
  def cleanup_cancelled_concoction(id) do
    update_concoction(id, %{status: "cancelled", assigned_brewer_id: nil})

    try do
      Apothecary.DevServer.stop_server(id)
    catch
      :exit, reason ->
        Logger.warning(
          "cleanup_cancelled_concoction: DevServer.stop_server failed for #{id}: #{inspect(reason)}"
        )
    end

    Apothecary.WorktreeManager.release(id)
  end

  # --- Ingredient Operations ---

  def create_ingredient(attrs) do
    id = generate_id("t")
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    record =
      {:apothecary_ingredients, id, attrs[:concoction_id] || attrs[:parent],
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
        {:ok, Apothecary.Ingredient.from_record(record)}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  def get_ingredient(id) do
    case :mnesia.dirty_read(:apothecary_ingredients, id) do
      [record] -> {:ok, Apothecary.Ingredient.from_record(record)}
      [] -> {:error, :not_found}
    end
  end

  def list_all_ingredients do
    :mnesia.dirty_match_object({:apothecary_ingredients, :_, :_, :_, :_, :_, :_})
    |> Enum.map(&Apothecary.Ingredient.from_record/1)
  end

  def list_ingredients(filters \\ []) do
    ingredients = list_all_ingredients()

    ingredients
    |> maybe_filter(:concoction_id, filters[:concoction_id])
    |> maybe_filter(:status, filters[:status])
  end

  def update_ingredient(id, changes) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_ingredients, id) do
          [record] ->
            updated = apply_ingredient_changes(record, changes)
            :mnesia.write(updated)
            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        schedule_broadcast()
        {:ok, Apothecary.Ingredient.from_record(record)}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Close an ingredient and unblock dependents."
  def close_ingredient(id, _reason \\ "Completed") do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_ingredients, id) do
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
              maybe_unblock_ingredient(dep_id)
            end)

            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        schedule_broadcast()
        {:ok, Apothecary.Ingredient.from_record(record)}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Add a note to a concoction or ingredient."
  def add_note(id, note) do
    id = to_string(id)

    if String.starts_with?(id, "wt-") do
      append_note(:apothecary_concoctions, id, 9, note, &Apothecary.Concoction.from_record/1)
    else
      append_note(:apothecary_ingredients, id, 6, note, &Apothecary.Ingredient.from_record/1)
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
        case :mnesia.read(:apothecary_ingredients, blocked_id) do
          [blocked] ->
            blocked_data = elem(blocked, 6)
            blockers = Enum.uniq([blocker_id | blocked_data[:blockers] || []])

            blocked =
              update_record_data(blocked, 6, fn data -> Map.put(data, :blockers, blockers) end)

            # If blocker is not done, set blocked to "blocked"
            blocked =
              case :mnesia.read(:apothecary_ingredients, to_string(blocker_id)) do
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
        case :mnesia.read(:apothecary_ingredients, to_string(blocker_id)) do
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

        case :mnesia.read(:apothecary_ingredients, current_id) do
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
        case :mnesia.read(:apothecary_ingredients, blocked_id) do
          [blocked] ->
            blocked_data = elem(blocked, 6)
            blockers = List.delete(blocked_data[:blockers] || [], blocker_id)

            blocked =
              update_record_data(blocked, 6, fn data -> Map.put(data, :blockers, blockers) end)

            # Check if all remaining blockers are done
            all_done =
              Enum.all?(blockers, fn bid ->
                case :mnesia.read(:apothecary_ingredients, bid) do
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
        case :mnesia.read(:apothecary_ingredients, blocker_id) do
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

  def ready_ingredients(concoction_id) do
    ingredients = list_ingredients(concoction_id: concoction_id)
    ingredient_status_map = Map.new(ingredients, fn t -> {t.id, t.status} end)
    Enum.filter(ingredients, &ingredient_ready?(&1, ingredient_status_map))
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    # Recover orphaned concoctions after brewers have had time to start
    Process.send_after(self(), :recover_orphans, 10_000)
    {:ok, %{broadcast_timer: nil}}
  end

  @impl true
  def handle_info(:recover_orphans, state) do
    # Only requeue concoctions whose assigned brewer isn't actually running
    active_brewer_ids = get_active_brewer_ids()

    case requeue_all_orphans(active_brewer_ids) do
      {:ok, 0} -> :ok
      {:ok, count} -> Logger.info("Recovered #{count} orphaned concoction(s) on startup")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:do_broadcast, state) do
    task_state = get_state()
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:ingredients_update, task_state})
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

  defp schedule_broadcast_timer(state) do
    if state.broadcast_timer do
      Process.cancel_timer(state.broadcast_timer)
    end

    timer = Process.send_after(self(), :do_broadcast, @broadcast_debounce_ms)
    %{state | broadcast_timer: timer}
  end

  # --- Private: ID Generation ---

  defp generate_id(prefix) do
    hex = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
    "#{prefix}-#{hex}"
  end

  # --- Private: Ready Computation ---

  defp compute_ready_concoctions(concoctions) do
    # Pre-fetch all concoctions into a status map for O(1) lookups
    wt_status_map = Map.new(concoctions, fn wt -> {wt.id, wt.status} end)
    Enum.filter(concoctions, &concoction_ready?(&1, wt_status_map))
  end

  defp concoction_ready?(
         %{status: status, assigned_brewer_id: nil, parent_concoction_id: nil},
         _map
       )
       when status in ["open", "revision_needed"],
       do: true

  defp concoction_ready?(
         %{status: status, assigned_brewer_id: nil, parent_concoction_id: pid},
         wt_status_map
       )
       when status in ["open", "revision_needed"] and not is_nil(pid) do
    Map.get(wt_status_map, pid) in ["done", "merged"]
  end

  # PR is open but new ingredients were added — redispatch to work on them
  defp concoction_ready?(%{status: "pr_open", assigned_brewer_id: nil, id: id}, _map) do
    list_ingredients(concoction_id: id, status: "open") |> Enum.any?()
  end

  defp concoction_ready?(_, _map), do: false

  defp ingredient_ready?(%{status: "open", blockers: []}, _ingredient_status_map), do: true

  defp ingredient_ready?(%{status: "open", blockers: blockers}, ingredient_status_map) do
    Enum.all?(blockers, fn blocker_id ->
      Map.get(ingredient_status_map, blocker_id) == "done"
    end)
  end

  defp ingredient_ready?(_, _ingredient_status_map), do: false

  # --- Private: Stats ---

  defp compute_stats(items) do
    by_status = Enum.group_by(items, & &1.status)

    %{
      "total" => length(items),
      "open" => length(by_status["open"] || []),
      "in_progress" => length(by_status["in_progress"] || []),
      "done" => length(by_status["done"] || []),
      "blocked" => length(by_status["blocked"] || []),
      "pr_open" => length(by_status["pr_open"] || []),
      "revision_needed" => length(by_status["revision_needed"] || []),
      "merged" => length(by_status["merged"] || [])
    }
  end

  # --- Private: Record Manipulation ---

  defp apply_concoction_changes(record, changes) do
    {table, id, status, title, priority, git_path, git_branch, parent_concoction_id,
     assigned_brewer_id, data} = record

    now = DateTime.utc_now() |> DateTime.to_iso8601()

    status = Map.get(changes, :status, status)
    title = Map.get(changes, :title, title)
    priority = Map.get(changes, :priority, priority)
    git_path = Map.get(changes, :git_path, git_path)
    git_branch = Map.get(changes, :git_branch, git_branch)
    parent_concoction_id = Map.get(changes, :parent_concoction_id, parent_concoction_id)

    assigned_brewer_id =
      if Map.has_key?(changes, :assigned_brewer_id),
        do: changes.assigned_brewer_id,
        else: assigned_brewer_id

    data =
      data
      |> maybe_put(:description, changes[:description])
      |> maybe_put(:notes, changes[:notes])
      |> maybe_put(:pr_url, changes[:pr_url])
      |> maybe_put(:blockers, changes[:blockers])
      |> maybe_put(:dependents, changes[:dependents])
      |> Map.put(:updated_at, now)

    {table, id, status, title, priority, git_path, git_branch, parent_concoction_id,
     assigned_brewer_id, data}
  end

  defp apply_ingredient_changes(record, changes) do
    {table, id, concoction_id, status, title, priority, data} = record
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    concoction_id = Map.get(changes, :concoction_id, concoction_id)
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

    {table, id, concoction_id, status, title, priority, data}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp update_record_data(record, index, fun) do
    data = elem(record, index)
    put_elem(record, index, fun.(data))
  end

  defp maybe_unblock_ingredient(ingredient_id) do
    case :mnesia.read(:apothecary_ingredients, ingredient_id) do
      [record] ->
        if elem(record, 3) == "blocked" do
          data = elem(record, 6)
          blockers = data[:blockers] || []

          all_done =
            Enum.all?(blockers, fn bid ->
              case :mnesia.read(:apothecary_ingredients, bid) do
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
        if agent.current_concoction, do: [agent.current_concoction.id], else: []
      end)
    rescue
      _ -> []
    catch
      :exit, _ -> []
    end
  end

  # --- Private: Filtering ---

  defp maybe_filter(items, _field, nil), do: items

  defp maybe_filter(items, field, value) do
    value = to_string(value)
    Enum.filter(items, fn item -> to_string(Map.get(item, field)) == value end)
  end
end
