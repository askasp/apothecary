defmodule ApothecaryWeb.TaskDetailLive do
  use ApothecaryWeb, :live_view

  alias Apothecary.{Beads, Poller}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket), do: Poller.subscribe()

    socket =
      socket
      |> assign(:page_title, "Task #{id}")
      |> assign(:task_id, id)
      |> assign_task(id)

    {:ok, socket}
  end

  @impl true
  def handle_info({:beads_update, _state}, socket) do
    {:noreply, assign_task(socket, socket.assigns.task_id)}
  end

  @impl true
  def handle_event("claim", _params, socket) do
    case Beads.claim(socket.assigns.task_id) do
      {:ok, _} ->
        Poller.force_refresh()
        {:noreply, put_flash(socket, :info, "Task claimed")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to claim: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    case Beads.close(socket.assigns.task_id) do
      {:ok, _} ->
        Poller.force_refresh()
        {:noreply, put_flash(socket, :info, "Task closed")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to close: #{inspect(reason)}")}
    end
  end

  defp assign_task(socket, id) do
    task =
      case Beads.show(id) do
        {:ok, task} -> task
        {:error, _} -> nil
      end

    dep_tree =
      case Beads.dep_tree(id) do
        {:ok, tree} -> tree
        {:error, _} -> ""
      end

    socket
    |> assign(:task, task)
    |> assign(:dep_tree, dep_tree)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.link>
          <h1 class="text-xl font-bold">Task {@task_id}</h1>
        </div>

        <%= if @task do %>
          <div class="bg-base-200 rounded-box p-6 space-y-4">
            <div class="flex items-center gap-3 flex-wrap">
              <.status_badge status={@task.status} />
              <.priority_badge priority={@task.priority} />
              <span :if={@task.type} class="badge badge-sm badge-outline">{@task.type}</span>
              <span :if={@task.assigned_to} class="badge badge-sm badge-info">
                {@task.assigned_to}
              </span>
            </div>

            <h2 class="text-lg font-semibold">{@task.title}</h2>

            <p :if={@task.description} class="text-base-content/70 whitespace-pre-wrap">
              {@task.description}
            </p>

            <div class="flex gap-2">
              <button phx-click="claim" class="btn btn-sm btn-primary">Claim</button>
              <button phx-click="close" class="btn btn-sm btn-error btn-soft">Close</button>
            </div>
          </div>

          <div :if={@task.blockers != []} class="space-y-2">
            <h3 class="font-semibold">Blocked By</h3>
            <div class="flex gap-2 flex-wrap">
              <.link
                :for={b <- @task.blockers}
                navigate={~p"/tasks/#{b}"}
                class="badge badge-sm badge-outline link"
              >
                {b}
              </.link>
            </div>
          </div>

          <div :if={@task.dependents != []} class="space-y-2">
            <h3 class="font-semibold">Blocks</h3>
            <div class="flex gap-2 flex-wrap">
              <.link
                :for={d <- @task.dependents}
                navigate={~p"/tasks/#{d}"}
                class="badge badge-sm badge-outline link"
              >
                {d}
              </.link>
            </div>
          </div>

          <div :if={@dep_tree != ""} class="space-y-2">
            <h3 class="font-semibold">Dependency Tree</h3>
            <pre class="bg-base-300 p-4 rounded-box text-sm overflow-x-auto">{@dep_tree}</pre>
          </div>
        <% else %>
          <div class="text-center py-12">
            <p class="text-error">Task not found</p>
            <.link navigate={~p"/"} class="btn btn-sm btn-ghost mt-4">Back to Dashboard</.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
