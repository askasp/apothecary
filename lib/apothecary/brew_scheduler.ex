defmodule Apothecary.BrewScheduler do
  @moduledoc """
  Schedules recurring brews based on cron expressions.

  On startup, loads all enabled recipes and calculates the time until each
  should fire next. Uses Process.send_after to trigger worktree creation
  at the right time. Naturally handles reboots by recalculating on startup.

  Subscribes to recipe PubSub to react to recipe changes (create, toggle, delete, update).
  """

  use GenServer
  require Logger

  # timers is a map of recipe_id => timer_ref
  defstruct timers: %{}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get the current state of the scheduler (for debugging/dashboard)."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    Apothecary.Worktrees.subscribe_recipes()
    # Delay initial scheduling to ensure Mnesia tables are ready
    Process.send_after(self(), :init_schedules, 2_000)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_info(:init_schedules, state) do
    state = schedule_all_recipes(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:fire_recipe, recipe_id}, state) do
    state = fire_recipe(recipe_id, state)
    {:noreply, state}
  end

  # React to recipe PubSub changes
  @impl true
  def handle_info({:recipe_created, recipe}, state) do
    state = schedule_recipe(recipe, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:recipe_toggled, recipe}, state) do
    state = reschedule_recipe(recipe, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:recipe_updated, recipe}, state) do
    state = reschedule_recipe(recipe, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:recipe_deleted, recipe}, state) do
    state = cancel_timer(recipe.id, state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    recipes = Apothecary.Worktrees.list_recipes()

    scheduled =
      Enum.map(recipes, fn recipe ->
        %{
          id: recipe.id,
          title: recipe.title,
          schedule: recipe.schedule,
          enabled: recipe.enabled,
          last_run_at: recipe.last_run_at,
          next_run_at: recipe.next_run_at,
          has_timer: Map.has_key?(state.timers, recipe.id)
        }
      end)

    {:reply, %{scheduled: scheduled, timer_count: map_size(state.timers)}, state}
  end

  # --- Private ---

  defp schedule_all_recipes(state) do
    recipes = Apothecary.Worktrees.list_recipes(enabled: true)
    Logger.info("BrewScheduler: loading #{length(recipes)} enabled recipe(s)")

    Enum.reduce(recipes, state, fn recipe, acc ->
      schedule_recipe(recipe, acc)
    end)
  end

  defp schedule_recipe(%{enabled: false} = _recipe, state), do: state

  defp schedule_recipe(recipe, state) do
    case next_run_ms(recipe.schedule) do
      {:ok, ms, next_dt} ->
        state = cancel_timer(recipe.id, state)
        timer = Process.send_after(self(), {:fire_recipe, recipe.id}, ms)
        next_iso = DateTime.to_iso8601(next_dt)

        Logger.info(
          "BrewScheduler: scheduled #{recipe.id} (#{recipe.title}) in #{div(ms, 1_000)}s at #{next_iso}"
        )

        # Update next_run_at in the database
        update_next_run(recipe.id, next_iso)

        %{state | timers: Map.put(state.timers, recipe.id, timer)}

      {:error, reason} ->
        Logger.warning("BrewScheduler: failed to schedule #{recipe.id}: #{inspect(reason)}")
        state
    end
  end

  defp reschedule_recipe(recipe, state) do
    state = cancel_timer(recipe.id, state)

    if recipe.enabled do
      schedule_recipe(recipe, state)
    else
      state
    end
  end

  defp cancel_timer(recipe_id, state) do
    case Map.get(state.timers, recipe_id) do
      nil ->
        state

      timer ->
        Process.cancel_timer(timer)
        %{state | timers: Map.delete(state.timers, recipe_id)}
    end
  end

  defp fire_recipe(recipe_id, state) do
    case Apothecary.Worktrees.get_recipe(recipe_id) do
      {:ok, recipe} ->
        if recipe.enabled do
          Logger.info("BrewScheduler: firing recipe #{recipe.id} (#{recipe.title})")

          # Create a worktree from the recipe
          worktree_attrs = %{
            title: recipe.title,
            description: recipe.description,
            priority: recipe.priority || 3
          }

          case Apothecary.Worktrees.create_worktree(worktree_attrs) do
            {:ok, worktree} ->
              Logger.info(
                "BrewScheduler: created worktree #{worktree.id} from recipe #{recipe.id}"
              )

            {:error, reason} ->
              Logger.error(
                "BrewScheduler: failed to create worktree from recipe #{recipe.id}: #{inspect(reason)}"
              )
          end

          # Schedule next run
          state = %{state | timers: Map.delete(state.timers, recipe_id)}

          case next_run_ms(recipe.schedule) do
            {:ok, ms, next_dt} ->
              next_iso = DateTime.to_iso8601(next_dt)
              Apothecary.Worktrees.mark_recipe_run(recipe_id, next_iso)
              timer = Process.send_after(self(), {:fire_recipe, recipe_id}, ms)

              Logger.info(
                "BrewScheduler: next run for #{recipe.id} in #{div(ms, 1_000)}s at #{next_iso}"
              )

              %{state | timers: Map.put(state.timers, recipe_id, timer)}

            {:error, reason} ->
              Logger.warning(
                "BrewScheduler: failed to schedule next run for #{recipe.id}: #{inspect(reason)}"
              )

              Apothecary.Worktrees.mark_recipe_run(recipe_id, nil)
              state
          end
        else
          state
        end

      {:error, :not_found} ->
        Logger.warning("BrewScheduler: recipe #{recipe_id} not found, skipping")
        %{state | timers: Map.delete(state.timers, recipe_id)}
    end
  end

  defp next_run_ms(schedule) when is_binary(schedule) do
    case Crontab.CronExpression.Parser.parse(schedule) do
      {:ok, cron} ->
        now = DateTime.utc_now() |> DateTime.to_naive()

        case Crontab.Scheduler.get_next_run_date(cron, now) do
          {:ok, next_naive} ->
            next_dt = DateTime.from_naive!(next_naive, "Etc/UTC")
            now_dt = DateTime.utc_now()
            diff_ms = DateTime.diff(next_dt, now_dt, :millisecond)
            # Ensure at least 1 second to avoid tight loops
            {:ok, max(diff_ms, 1_000), next_dt}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_next_run(recipe_id, next_iso) do
    :mnesia.transaction(fn ->
      case :mnesia.read(:apothecary_recipes, recipe_id) do
        [record] ->
          data = elem(record, 7)
          updated = put_elem(record, 7, Map.put(data, :next_run_at, next_iso))
          :mnesia.write(updated)

        [] ->
          :ok
      end
    end)
  end
end
