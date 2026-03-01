defmodule Apothecary.AgentWorker do
  @moduledoc """
  GenServer managing a single Claude Code agent process.

  Lifecycle:
  1. Starts in :idle state, registered with the Dispatcher
  2. Receives a task assignment from the Dispatcher
  3. Checks out a worktree from WorktreeManager
  4. Spawns `claude -p "<prompt>" --dangerously-skip-permissions` as a Port
  5. Streams output via PubSub for LiveView consumption
  6. On completion, closes the bead, releases worktree, signals Dispatcher
  """

  use GenServer
  require Logger

  @pubsub Apothecary.PubSub
  @max_output_lines 500

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Assign a task to this agent."
  def assign_task(pid, task) do
    GenServer.cast(pid, {:assign_task, task})
  end

  @doc "Get the current state of this agent."
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)

    state = %Apothecary.AgentState{
      id: id,
      status: :idle
    }

    Apothecary.Dispatcher.agent_idle(self())
    broadcast_state(state)

    {:ok, %{agent: state, port: nil, buffer: ""}}
  end

  @impl true
  def handle_cast({:assign_task, task}, %{agent: agent} = state) do
    Logger.info("Agent #{agent.id} assigned task #{task.id}: #{task.title}")

    agent = %{agent | status: :starting, current_task: task, started_at: DateTime.utc_now()}
    broadcast_state(agent)

    case Apothecary.WorktreeManager.checkout(agent.id) do
      {:ok, path, branch} ->
        agent = %{agent | worktree_path: path, branch: branch, status: :working, output: []}
        port = spawn_claude(agent, task)
        broadcast_state(agent)
        {:noreply, %{state | agent: agent, port: port}}

      {:error, reason} ->
        Logger.error("Agent #{agent.id} failed to checkout worktree: #{inspect(reason)}")
        agent = %{agent | status: :error}
        broadcast_state(agent)
        Apothecary.Dispatcher.agent_idle(self())
        {:noreply, %{state | agent: agent}}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.agent, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port, agent: agent} = state) do
    # Port data may arrive in chunks that don't align with newlines.
    # Buffer partial lines and only process complete lines.
    buffered = state.buffer <> data

    {complete_lines, remainder} =
      case String.split(buffered, "\n") do
        [single] -> {[], single}
        parts -> {Enum.slice(parts, 0..-2//1), List.last(parts)}
      end

    display_lines = Enum.flat_map(complete_lines, &parse_stream_line/1)

    output =
      (agent.output ++ display_lines)
      |> Enum.take(-@max_output_lines)

    agent = %{agent | output: output}

    if display_lines != [] do
      broadcast_output(agent.id, display_lines)
      report_state(agent)
    end

    {:noreply, %{state | agent: agent, buffer: remainder}}
  end

  @impl true
  def handle_info({port, {:exit_status, 0}}, %{port: port, agent: agent} = state) do
    Logger.info("Agent #{agent.id} completed task #{agent.current_task.id}")

    Apothecary.Beads.close(agent.current_task.id, "Completed by agent #{agent.id}")
    Apothecary.WorktreeManager.release(agent.id)
    Apothecary.Poller.force_refresh()

    agent = %{
      agent
      | status: :idle,
        current_task: nil,
        port: nil,
        worktree_path: nil,
        branch: nil
    }

    broadcast_state(agent)
    Apothecary.Dispatcher.agent_idle(self())

    {:noreply, %{state | agent: agent, port: nil}}
  end

  @impl true
  def handle_info({port, {:exit_status, code}}, %{port: port, agent: agent} = state) do
    Logger.warning("Agent #{agent.id} task #{agent.current_task.id} exited with code #{code}")

    if agent.current_task do
      Apothecary.Beads.update_notes(
        agent.current_task.id,
        "Agent #{agent.id} failed with exit code #{code}"
      )
    end

    Apothecary.WorktreeManager.release(agent.id)
    Apothecary.Poller.force_refresh()

    agent = %{
      agent
      | status: :idle,
        current_task: nil,
        port: nil,
        worktree_path: nil,
        branch: nil
    }

    broadcast_state(agent)
    Apothecary.Dispatcher.agent_idle(self())

    {:noreply, %{state | agent: agent, port: nil}}
  end

  @impl true
  def terminate(_reason, %{port: port}) when not is_nil(port) do
    Port.close(port)
  end

  def terminate(_reason, _state), do: :ok

  # Private

  defp spawn_claude(agent, task) do
    claude_path = Application.get_env(:apothecary, :claude_path, "claude")

    prompt = build_prompt(task, agent.worktree_path)

    executable = System.find_executable(claude_path)

    unless executable do
      raise "Claude Code executable not found: #{claude_path}"
    end

    args = [
      "-p",
      prompt,
      "--dangerously-skip-permissions",
      "--output-format",
      "stream-json"
    ]

    Port.open({:spawn_executable, executable}, [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      {:args, args},
      {:cd, to_charlist(agent.worktree_path)}
    ])
  end

  defp build_prompt(task, worktree_path) do
    project_dir = Application.get_env(:apothecary, :project_dir)

    claude_md =
      case File.read(Path.join(project_dir, "CLAUDE.md")) do
        {:ok, content} -> content
        _ -> ""
      end

    agents_md =
      case File.read(Path.join(project_dir, "AGENTS.md")) do
        {:ok, content} -> content
        _ -> ""
      end

    """
    You are an autonomous coding agent working in: #{worktree_path}

    ## Your Task
    ID: #{task.id}
    Title: #{task.title}
    Type: #{task.type || "task"}
    Priority: #{task.priority || "medium"}
    Description: #{task.description || task.title}

    ## Instructions
    1. Read and understand the codebase
    2. Implement the task described above
    3. Run tests to verify your changes work
    4. Commit your changes with a descriptive message including the task ID
    5. Push your branch to origin: `git push -u origin $(git branch --show-current)`
    6. Log progress with: `bd update #{task.id} --notes "Completed: <summary>"`

    ## Rules
    - You are on a feature branch in a git worktree, NOT main
    - NEVER push to main or merge into main
    - Commit and push when done
    - Include "#{task.id}" in your commit message
    - If the task is too large, decompose it with `bd create` and `bd dep add`
    - Use `bd update #{task.id} --notes "..."` to log progress

    ## Beads Task Tracking
    This project uses beads (bd CLI) for task tracking. The beads database is
    shared across all agents via git. You can use these commands:
    - `bd show #{task.id} --json` to see full task details
    - `bd update #{task.id} --notes "progress"` to log progress
    - `bd create "subtask" -t task -p 1 --parent #{task.id} --json` to create subtasks
    - `bd dep add <blocked_id> <blocker_id>` to wire dependencies
    - `bd ready --json` to see what tasks are unblocked

    #{if claude_md != "", do: "## Project Guidelines (CLAUDE.md)\n#{claude_md}", else: ""}
    #{if agents_md != "", do: "## Agent Guidelines (AGENTS.md)\n#{agents_md}", else: ""}
    """
  end

  defp parse_stream_line(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "assistant", "message" => %{"content" => content}}} ->
        extract_text_from_content(content)

      {:ok, %{"type" => "result", "result" => result}} ->
        [result]

      {:ok, %{"type" => "tool_use", "tool" => tool, "input" => _}} ->
        ["[tool: #{tool}]"]

      {:ok, %{"type" => "tool_result"}} ->
        []

      {:ok, %{"type" => "system"}} ->
        []

      {:ok, _event} ->
        # Unknown event type — show raw for debugging
        []

      {:error, _} ->
        # Not JSON — show as plain text (e.g. stderr output)
        if String.trim(line) != "", do: [line], else: []
    end
  end

  defp extract_text_from_content(content) when is_list(content) do
    Enum.flat_map(content, fn
      %{"type" => "text", "text" => text} -> [text]
      %{"type" => "tool_use", "name" => name} -> ["[tool: #{name}]"]
      _ -> []
    end)
  end

  defp extract_text_from_content(content) when is_binary(content), do: [content]
  defp extract_text_from_content(_), do: []

  defp broadcast_state(agent) do
    Phoenix.PubSub.broadcast(@pubsub, "agent:#{agent.id}", {:agent_state, agent})
    report_state(agent)
  end

  defp broadcast_output(agent_id, lines) do
    Phoenix.PubSub.broadcast(@pubsub, "agent:#{agent_id}", {:agent_output, lines})
  end

  defp report_state(agent) do
    GenServer.cast(Apothecary.Dispatcher, {:agent_update, self(), agent})
  end
end
