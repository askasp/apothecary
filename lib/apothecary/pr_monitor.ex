defmodule Apothecary.PRMonitor do
  @moduledoc """
  Polls GitHub for PR status changes on worktrees with status "pr_open".

  - MERGED → mark_merged + cleanup_merged_worktree (releases disk, sets done)
  - CHANGES_REQUESTED → mark_revision_needed (dispatcher picks it up)
  - CLOSED without merge → cleanup_cancelled_worktree (releases disk, sets cancelled)
  - OPEN with no changes requested → no action
  """

  use GenServer
  require Logger

  @poll_interval_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_poll()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    check_all_prs()

    schedule_poll()
    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp check_all_prs do
    worktrees = Apothecary.Worktrees.pr_open_worktrees()

    Enum.each(worktrees, fn wt ->
      if wt.pr_url do
        check_pr(wt)
      else
        Logger.warning("PRMonitor: worktree #{wt.id} is pr_open but has no pr_url")
      end
    end)
  end

  defp check_pr(wt) do
    project_dir = resolve_project_dir(wt)

    case Apothecary.Git.pr_status(project_dir, wt.pr_url) do
      {:ok, %{"state" => "MERGED"}} ->
        Logger.info("PRMonitor: PR merged for #{wt.id}, cleaning up")
        Apothecary.Worktrees.add_note(wt.id, "PR merged: #{wt.pr_url}")
        Apothecary.Worktrees.cleanup_merged_worktree(wt.id)

        if Apothecary.platform_mode?() do
          Apothecary.DeploymentServer.rebuild_for_branch(wt.project_id, "main")
        end

      {:ok, %{"state" => "OPEN", "reviewDecision" => "CHANGES_REQUESTED"}} ->
        Logger.info("PRMonitor: Changes requested on #{wt.id}, marking for revision")
        Apothecary.Worktrees.add_note(wt.id, "PR changes requested — re-dispatching brewer")
        Apothecary.Worktrees.mark_revision_needed(wt.id)

      {:ok, %{"state" => "CLOSED"}} ->
        Logger.info("PRMonitor: PR closed without merge for #{wt.id}, cleaning up")
        Apothecary.Worktrees.add_note(wt.id, "PR closed without merge: #{wt.pr_url}")
        Apothecary.Worktrees.cleanup_cancelled_worktree(wt.id)

      {:ok, %{"state" => "OPEN"}} ->
        :ok

      {:error, reason} ->
        Logger.warning("PRMonitor: Failed to check PR for #{wt.id}: #{inspect(reason)}")
    end
  end

  defp resolve_project_dir(%{project_id: project_id}) when not is_nil(project_id) do
    case Apothecary.Projects.get(project_id) do
      {:ok, project} -> project.path
      _ -> nil
    end
  end

  defp resolve_project_dir(_), do: nil
end
