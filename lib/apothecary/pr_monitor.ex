defmodule Apothecary.PRMonitor do
  @moduledoc """
  Polls GitHub for PR status changes on concoctions with status "pr_open".

  - MERGED → mark_merged + cleanup_merged_concoction (releases disk, sets done)
  - CHANGES_REQUESTED → mark_revision_needed (dispatcher picks it up)
  - CLOSED without merge → cleanup_cancelled_concoction (releases disk, sets cancelled)
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
    # Only poll when in GitHub mode
    if Apothecary.Git.merge_mode() == :github do
      check_all_prs()
    end

    schedule_poll()
    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp check_all_prs do
    concoctions = Apothecary.Ingredients.pr_open_concoctions()

    Enum.each(concoctions, fn wt ->
      if wt.pr_url do
        check_pr(wt)
      else
        Logger.warning("PRMonitor: concoction #{wt.id} is pr_open but has no pr_url")
      end
    end)
  end

  defp check_pr(wt) do
    case Apothecary.Git.pr_status(wt.pr_url) do
      {:ok, %{"state" => "MERGED"}} ->
        Logger.info("PRMonitor: PR merged for #{wt.id}, cleaning up")
        Apothecary.Ingredients.add_note(wt.id, "PR merged: #{wt.pr_url}")
        Apothecary.Ingredients.cleanup_merged_concoction(wt.id)

      {:ok, %{"state" => "OPEN", "reviewDecision" => "CHANGES_REQUESTED"}} ->
        Logger.info("PRMonitor: Changes requested on #{wt.id}, marking for revision")
        Apothecary.Ingredients.add_note(wt.id, "PR changes requested — re-dispatching brewer")
        Apothecary.Ingredients.mark_revision_needed(wt.id)

      {:ok, %{"state" => "CLOSED"}} ->
        Logger.info("PRMonitor: PR closed without merge for #{wt.id}, cleaning up")
        Apothecary.Ingredients.add_note(wt.id, "PR closed without merge: #{wt.pr_url}")
        Apothecary.Ingredients.cleanup_cancelled_concoction(wt.id)

      {:ok, %{"state" => "OPEN"}} ->
        # No action needed — PR is open and awaiting review
        :ok

      {:error, reason} ->
        Logger.warning("PRMonitor: Failed to check PR for #{wt.id}: #{inspect(reason)}")
    end
  end
end
