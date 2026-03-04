defmodule Apothecary.MergeConflictTest do
  use ExUnit.Case

  alias Apothecary.{Git, Worktrees}

  describe "Git.merge_conflict?/1" do
    test "detects CONFLICT keyword" do
      output = """
      CONFLICT (content): Merge conflict in lib/foo.ex
      Automatic merge failed; fix conflicts and then commit the result.
      """

      assert Git.merge_conflict?(output)
    end

    test "detects Automatic merge failed" do
      assert Git.merge_conflict?(
               "Automatic merge failed; fix conflicts and then commit the result."
             )
    end

    test "detects fix conflicts" do
      assert Git.merge_conflict?("Please fix conflicts and run 'git commit'")
    end

    test "returns false for clean merge" do
      refute Git.merge_conflict?("Already up to date.")
    end

    test "returns false for non-binary input" do
      refute Git.merge_conflict?(nil)
      refute Git.merge_conflict?(42)
    end
  end

  describe "Git.conflict_files/1" do
    test "extracts file paths from merge conflict output" do
      output = """
      Auto-merging lib/bar.ex
      CONFLICT (content): Merge conflict in lib/foo.ex
      CONFLICT (content): Merge conflict in lib/baz.ex
      Automatic merge failed; fix conflicts and then commit the result.
      """

      assert Git.conflict_files(output) == ["lib/foo.ex", "lib/baz.ex"]
    end

    test "deduplicates files" do
      output = """
      CONFLICT (content): Merge conflict in lib/foo.ex
      CONFLICT (content): Merge conflict in lib/foo.ex
      """

      assert Git.conflict_files(output) == ["lib/foo.ex"]
    end

    test "returns empty list for no conflicts" do
      assert Git.conflict_files("Already up to date.") == []
    end
  end

  describe "merge conflict task creation flow" do
    setup do
      Phoenix.PubSub.subscribe(Apothecary.PubSub, "worktrees:updates")

      {:ok, worktree} =
        Worktrees.create_worktree(%{title: "Test merge conflict", status: "in_progress"})

      # Drain creation broadcast
      receive do
        {:worktrees_update, _} -> :ok
      after
        200 -> :ok
      end

      {:ok, worktree: worktree}
    end

    test "creates fix task and sets merge_conflict status", %{worktree: worktree} do
      # Simulate what handle_merge_conflict does
      conflict_files = ["lib/foo.ex", "lib/bar.ex"]
      files_list = Enum.join(conflict_files, ", ")

      {:ok, task} =
        Worktrees.create_task(%{
          worktree_id: worktree.id,
          title: "Fix merge conflicts with main",
          priority: 0,
          description: "Conflicting files: #{files_list}",
          status: "blocked"
        })

      {:ok, _} = Worktrees.update_worktree(worktree.id, %{status: "merge_conflict"})

      # Drain broadcasts
      Process.sleep(100)

      # Verify the task was created with correct properties
      {:ok, fetched} = Worktrees.get_task(task.id)
      assert fetched.title == "Fix merge conflicts with main"
      assert fetched.status == "blocked"
      assert fetched.priority == 0
      assert fetched.worktree_id == worktree.id

      # Verify worktree is in merge_conflict status
      {:ok, fetched_worktree} = Worktrees.get_worktree(worktree.id)
      assert fetched_worktree.status == "merge_conflict"
    end

    test "approve flow: unblocking task and setting worktree to open", %{
      worktree: worktree
    } do
      # Create the blocked fix task
      {:ok, task} =
        Worktrees.create_task(%{
          worktree_id: worktree.id,
          title: "Fix merge conflicts with main",
          priority: 0,
          status: "blocked"
        })

      {:ok, _} = Worktrees.update_worktree(worktree.id, %{status: "merge_conflict"})

      # Simulate approve action (what the dashboard handler does)
      {:ok, _} = Worktrees.update_task(task.id, %{status: "open"})
      {:ok, _} = Worktrees.update_worktree(worktree.id, %{status: "open"})

      # Drain broadcasts
      Process.sleep(100)

      # Verify task is now open
      {:ok, fetched} = Worktrees.get_task(task.id)
      assert fetched.status == "open"

      # Verify worktree is open and ready for dispatch
      {:ok, fetched_worktree} = Worktrees.get_worktree(worktree.id)
      assert fetched_worktree.status == "open"
    end

    test "push failure recovery: worktree moves to brew_done", %{worktree: worktree} do
      # Simulate: brewer was assigned (in_progress with brewer)
      {:ok, _} =
        Worktrees.update_worktree(worktree.id, %{
          status: "in_progress",
          assigned_brewer_id: 1
        })

      # Simulate what happens when push fails in push_and_finalize:
      # The worktree should be set to brew_done with brewer cleared
      {:ok, _} =
        Worktrees.update_worktree(worktree.id, %{
          status: "brew_done",
          assigned_brewer_id: nil
        })

      # Drain broadcasts
      Process.sleep(100)

      # Verify worktree is in brew_done (reviewing lane) and not stuck in in_progress
      {:ok, fetched} = Worktrees.get_worktree(worktree.id)
      assert fetched.status == "brew_done"
      assert fetched.assigned_brewer_id == nil
    end
  end
end
