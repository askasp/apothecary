defmodule Apothecary.BrewerSupervisor do
  @moduledoc "DynamicSupervisor for brewer processes."

  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a new brewer under this supervisor."
  def start_brewer(id) do
    spec = {Apothecary.Brewer, id: id}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc "Stop a brewer."
  def stop_brewer(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc "Count running brewers."
  def count do
    %{active: active} = DynamicSupervisor.count_children(__MODULE__)
    active
  end

  @doc "List all brewer PIDs."
  def brewers do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&is_pid/1)
  end
end
