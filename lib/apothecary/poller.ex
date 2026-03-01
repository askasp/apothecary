defmodule Apothecary.Poller do
  @moduledoc """
  GenServer that periodically polls the bd CLI and broadcasts
  state updates via PubSub for LiveView consumption.
  """

  use GenServer
  require Logger

  @pubsub Apothecary.PubSub
  @topic "beads:updates"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get the current cached state."
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc "Trigger an immediate poll."
  def force_refresh do
    GenServer.cast(__MODULE__, :poll)
  end

  @doc "Subscribe to beads update broadcasts."
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    project_dir = Application.get_env(:apothecary, :project_dir)
    poll_interval = Application.get_env(:apothecary, :poll_interval, 2_000)

    state = %{
      project_dir: project_dir,
      poll_interval: poll_interval,
      tasks: [],
      ready_tasks: [],
      stats: %{},
      last_poll: nil,
      error: nil
    }

    if project_dir do
      schedule_poll(0)
    else
      Logger.warning("Apothecary.Poller: no project_dir configured, poller idle")
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = do_poll(state)
    broadcast(state)
    schedule_poll(state.poll_interval)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:poll, state) do
    state = do_poll(state)
    broadcast(state)
    {:noreply, state}
  end

  # Private

  defp schedule_poll(interval) when is_integer(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp schedule_poll(_), do: :ok

  defp do_poll(%{project_dir: nil} = state), do: state

  defp do_poll(state) do
    tasks_task = Elixir.Task.async(fn -> Apothecary.Beads.list() end)
    ready_task = Elixir.Task.async(fn -> Apothecary.Beads.ready() end)
    stats_task = Elixir.Task.async(fn -> Apothecary.Beads.stats() end)

    %{
      state
      | tasks: unwrap(Elixir.Task.await(tasks_task, 10_000), []),
        ready_tasks: unwrap(Elixir.Task.await(ready_task, 10_000), []),
        stats: unwrap(Elixir.Task.await(stats_task, 10_000), %{}),
        last_poll: DateTime.utc_now(),
        error: nil
    }
  rescue
    e ->
      Logger.error("Poller error: #{inspect(e)}")
      %{state | error: Exception.message(e), last_poll: DateTime.utc_now()}
  end

  defp unwrap({:ok, value}, _default), do: value
  defp unwrap({:error, _}, default), do: default

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:beads_update, state})
  end
end
