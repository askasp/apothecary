defmodule Apothecary.AgentSupervisor do
  @moduledoc "DynamicSupervisor for agent worker processes."

  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a new agent worker under this supervisor."
  def start_agent(id) do
    spec = {Apothecary.AgentWorker, id: id}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc "Stop an agent worker."
  def stop_agent(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc "Count running agents."
  def count do
    %{active: active} = DynamicSupervisor.count_children(__MODULE__)
    active
  end

  @doc "List all agent worker PIDs."
  def agents do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&is_pid/1)
  end
end
