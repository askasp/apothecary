defmodule Apothecary.WorktreesBroadcastTest do
  use ExUnit.Case

  alias Apothecary.Worktrees

  setup do
    # Subscribe to PubSub to receive broadcast messages
    Phoenix.PubSub.subscribe(Apothecary.PubSub, "worktrees:updates")

    # Create a worktree + task for testing
    {:ok, worktree} =
      Worktrees.create_worktree(%{title: "Test worktree", status: "in_progress"})

    # Drain the creation broadcast
    receive do
      {:worktrees_update, _} -> :ok
    after
      200 -> :ok
    end

    {:ok, task} =
      Worktrees.create_task(%{
        title: "Test task",
        worktree_id: worktree.id
      })

    # Drain the creation broadcast
    receive do
      {:worktrees_update, _} -> :ok
    after
      200 -> :ok
    end

    %{worktree: worktree, task: task}
  end

  test "close_task broadcasts immediately", %{task: task} do
    {:ok, _closed} = Worktrees.close_task(task.id)

    # The broadcast should arrive immediately (within a few ms), not after the
    # 50ms debounce window. Use a tight timeout to verify immediacy.
    assert_receive {:worktrees_update, state}, 30

    # Verify the broadcast contains the updated task as done
    done = Enum.find(state.tasks, &(&1.id == task.id))
    assert done.status == "done"
  end

  test "completing multiple tasks broadcasts separately", %{
    worktree: worktree,
    task: task1
  } do
    {:ok, task2} =
      Worktrees.create_task(%{
        title: "Second task",
        worktree_id: worktree.id
      })

    # Drain creation broadcast
    receive do
      {:worktrees_update, _} -> :ok
    after
      200 -> :ok
    end

    # Complete first task
    {:ok, _} = Worktrees.close_task(task1.id)

    # Should get immediate broadcast showing first task done
    assert_receive {:worktrees_update, state1}, 30
    t1 = Enum.find(state1.tasks, &(&1.id == task1.id))
    t2 = Enum.find(state1.tasks, &(&1.id == task2.id))
    assert t1.status == "done"
    assert t2.status == "open"

    # Complete second task
    {:ok, _} = Worktrees.close_task(task2.id)

    # Should get another immediate broadcast showing both done
    assert_receive {:worktrees_update, state2}, 30
    t1 = Enum.find(state2.tasks, &(&1.id == task1.id))
    t2 = Enum.find(state2.tasks, &(&1.id == task2.id))
    assert t1.status == "done"
    assert t2.status == "done"
  end
end
