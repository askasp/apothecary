defmodule Apothecary.Brewer do
  @moduledoc """
  GenServer managing a single Claude Code agent process.

  Lifecycle:
  1. Starts in :idle state, registered with the Dispatcher
  2. Receives a worktree assignment from the Dispatcher
  3. Spawns `claude -p "<prompt>" --dangerously-skip-permissions` as a Port
  4. Streams output via PubSub for LiveView consumption
  5. On completion, closes the worktree, pushes branch, creates PR
  """

  use GenServer
  require Logger

  @pubsub Apothecary.PubSub
  @max_output_lines 500
  @error_display_time 30_000
  @stuck_timeout_ms 5 * 60 * 1_000
  @max_buffer_bytes 1_024 * 1_024

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Assign a worktree to this brewer."
  def assign_worktree(pid, worktree, worktree_path, branch, project_dir) do
    GenServer.cast(pid, {:assign_worktree, worktree, worktree_path, branch, project_dir})
  end

  @doc "Get the current state of this brewer."
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc "Send an instruction to the brewer's stdin (for interactive guidance)."
  def send_instruction(pid, text) do
    GenServer.cast(pid, {:send_instruction, text})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)

    state = %Apothecary.BrewerState{
      id: id,
      status: :idle
    }

    Apothecary.Dispatcher.agent_idle(self())
    broadcast_state(state)

    {:ok, %{agent: state, port: nil, buffer: "", worktree_id: nil, watchdog_timer: nil}}
  end

  @impl true
  def handle_cast(
        {:assign_worktree, worktree, worktree_path, branch, project_dir},
        %{agent: agent} = state
      ) do
    Logger.info("Brewer #{agent.id} assigned worktree #{worktree.id}: #{worktree.title}")

    agent = %{
      agent
      | status: :starting,
        current_worktree: worktree,
        started_at: DateTime.utc_now(),
        worktree_path: worktree_path,
        branch: branch,
        project_dir: project_dir
    }

    broadcast_state(agent)

    agent = %{agent | status: :working, output: []}
    is_question = worktree.kind == "question"

    tasks =
      if is_question do
        []
      else
        # Write MCP config so Claude can communicate with the orchestrator
        extra_mcps = Map.get(worktree, :mcp_servers) || %{}
        write_mcp_config(worktree_path, agent.id, worktree.id, extra_mcps, project_dir)
        # Write apothecary CLAUDE.md to the worktree's .claude/ directory
        write_claude_md(worktree_path)
        Apothecary.Worktrees.list_tasks(worktree_id: worktree.id)
      end

    case spawn_claude(agent, worktree, tasks) do
      {:ok, port, sandboxed} ->
        agent = %{agent | sandboxed: sandboxed}
        watchdog = schedule_watchdog()
        broadcast_state(agent)

        {:noreply,
         %{
           state
           | agent: agent,
             port: port,
             buffer: "",
             worktree_id: worktree.id,
             watchdog_timer: watchdog
         }}

      {:error, reason} ->
        error_msg = "[Failed to spawn claude: #{inspect(reason)}]"
        Logger.error("Brewer #{agent.id}: #{error_msg}")
        agent = %{agent | status: :error, output: [error_msg]}
        broadcast_state(agent)
        broadcast_output(agent.id, [error_msg])
        Apothecary.Worktrees.release_worktree(worktree.id)
        schedule_error_reset()
        {:noreply, %{state | agent: agent, worktree_id: worktree.id}}
    end
  end

  @impl true
  def handle_cast({:send_instruction, text}, %{port: port} = state) when not is_nil(port) do
    Port.command(port, text <> "\n")
    {:noreply, state}
  end

  def handle_cast({:send_instruction, _text}, state), do: {:noreply, state}

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.agent, state}
  end

  @impl true
  def handle_info({:accept_permissions, port}, %{port: port} = state) do
    Logger.info("Brewer #{state.agent.id} auto-accepting bypass permissions prompt")
    Port.command(port, "\e[B\r")
    {:noreply, state}
  end

  def handle_info({:accept_permissions, _stale_port}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port, agent: agent} = state) do
    data = strip_ansi(data)

    if data == "" do
      {:noreply, state}
    else
      buffered = state.buffer <> data

      # Guard against unbounded buffer growth
      buffered =
        if byte_size(buffered) > @max_buffer_bytes do
          Logger.warning(
            "Brewer #{agent.id} buffer exceeded #{div(@max_buffer_bytes, 1024)}KB, force-flushing"
          )

          buffered
        else
          buffered
        end

      {complete_lines, remainder} =
        if byte_size(buffered) > @max_buffer_bytes do
          # Force-flush: treat entire buffer as complete lines
          {String.split(buffered, "\n", trim: true), ""}
        else
          case String.split(buffered, "\n") do
            [single] -> {[], single}
            parts -> {Enum.slice(parts, 0..-2//1), List.last(parts)}
          end
        end

      display_lines = Enum.flat_map(complete_lines, &parse_stream_line/1)

      output =
        (agent.output ++ display_lines)
        |> Enum.take(-@max_output_lines)

      agent = %{agent | output: output}

      # Reset watchdog on output
      state = reset_watchdog(state)

      if display_lines != [] do
        broadcast_output(agent.id, display_lines)
        report_state(agent)
      end

      {:noreply, %{state | agent: agent, buffer: remainder}}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, 0}}, %{port: port, agent: agent} = state) do
    cancel_watchdog(state)
    remaining = flush_buffer(state.buffer)
    output = (agent.output ++ remaining) |> Enum.take(-@max_output_lines)
    agent = %{agent | output: output}

    if remaining != [] do
      broadcast_output(agent.id, remaining)
    end

    Logger.info("Brewer #{agent.id} completed worktree #{state.worktree_id}")

    worktree_id = state.worktree_id
    wt = agent.current_worktree

    if wt && wt.kind == "question" do
      # Questions: save the response as notes and close — no push/PR
      response = Enum.join(output, "\n")
      Apothecary.Worktrees.add_note(worktree_id, "Answer:\n#{response}")
      Apothecary.Worktrees.close_worktree(worktree_id)
    else
      # Tasks: record session summary, push, and create PR
      add_session_summary(worktree_id, agent)
      finalize_worktree(worktree_id, agent)
    end

    # Trigger refresh and go idle
    Apothecary.Worktrees.force_refresh()

    agent = %{
      agent
      | status: :idle,
        current_worktree: nil,
        project_dir: nil,
        worktree_path: nil,
        branch: nil
    }

    broadcast_state(agent)
    Apothecary.Dispatcher.agent_idle(self())

    {:noreply,
     %{state | agent: agent, port: nil, buffer: "", worktree_id: nil, watchdog_timer: nil}}
  end

  @impl true
  def handle_info({port, {:exit_status, code}}, %{port: port, agent: agent} = state) do
    cancel_watchdog(state)
    remaining = flush_buffer(state.buffer)
    output = (agent.output ++ remaining) |> Enum.take(-@max_output_lines)

    error_msg = "[Claude exited with code #{code}]"
    output = output ++ [error_msg]

    Logger.warning("Brewer #{agent.id} worktree #{state.worktree_id} exited with code #{code}")

    if output != [error_msg] do
      Logger.warning("Brewer #{agent.id} captured output:\n#{Enum.join(output, "\n")}")
    end

    if state.worktree_id do
      add_crash_context(
        state.worktree_id,
        agent,
        "Brewer #{agent.id} failed (exit code #{code}).",
        output
      )

      Apothecary.Worktrees.release_worktree(state.worktree_id)
    end

    agent = %{agent | status: :error, output: output}
    broadcast_state(agent)
    broadcast_output(agent.id, remaining ++ [error_msg])

    schedule_error_reset()

    {:noreply, %{state | agent: agent, port: nil, buffer: "", watchdog_timer: nil}}
  end

  @impl true
  def handle_info(:reset_after_error, %{agent: agent} = state) do
    if agent.status == :error do
      Logger.info("Brewer #{agent.id} resetting after error")

      agent = %{
        agent
        | status: :idle,
          current_worktree: nil,
          worktree_path: nil,
          branch: nil
      }

      broadcast_state(agent)
      Apothecary.Dispatcher.agent_idle(self())
      {:noreply, %{state | agent: agent, worktree_id: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:watchdog, %{port: port, agent: agent} = state) when not is_nil(port) do
    Logger.warning(
      "Brewer #{agent.id} stuck — no output for #{div(@stuck_timeout_ms, 60_000)} minutes. Killing."
    )

    Port.close(port)

    if state.worktree_id do
      add_crash_context(
        state.worktree_id,
        agent,
        "Brewer #{agent.id} killed by watchdog (stuck for #{div(@stuck_timeout_ms, 60_000)} min).",
        agent.output
      )

      Apothecary.Worktrees.release_worktree(state.worktree_id)
    end

    agent = %{agent | status: :error, output: agent.output ++ ["[Killed by watchdog: stuck]"]}
    broadcast_state(agent)
    schedule_error_reset()

    {:noreply, %{state | agent: agent, port: nil, buffer: "", watchdog_timer: nil}}
  end

  def handle_info(:watchdog, state), do: {:noreply, state}

  @impl true
  def handle_info(msg, %{agent: agent} = state) do
    Logger.warning("Brewer #{agent.id} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{port: port, agent: agent}) when not is_nil(port) do
    Port.close(port)
    cleanup_sandbox_profile(agent.id)
  end

  def terminate(_reason, %{agent: agent}) do
    cleanup_sandbox_profile(agent.id)
  end

  def terminate(_reason, _state), do: :ok

  # Private — Session summary on clean exit

  defp add_session_summary(worktree_id, agent) do
    tasks = Apothecary.Worktrees.list_tasks(worktree_id: worktree_id)

    completed =
      tasks
      |> Enum.filter(&(&1.status == "done"))
      |> Enum.map(&"  - #{&1.id}: #{&1.title}")

    remaining =
      tasks
      |> Enum.reject(&(&1.status == "done"))
      |> Enum.map(&"  - #{&1.id}: #{&1.title} (#{&1.status})")

    git_log =
      case Apothecary.Git.worktree_log(agent.project_dir, agent.worktree_path, 10) do
        {:ok, log} when log != "" -> "\nCommits made:\n#{log}"
        _ -> ""
      end

    # Include diff stat so the next brewer sees total scope of changes
    diff_stat =
      case Apothecary.Git.worktree_diff_stat(agent.project_dir, agent.worktree_path) do
        {:ok, stat} when stat != "" -> "\nFiles changed (branch vs main):\n#{stat}"
        _ -> ""
      end

    parts =
      [
        "Session completed by Brewer #{agent.id}.",
        if(completed != [],
          do: "Completed tasks:\n#{Enum.join(completed, "\n")}",
          else: nil
        ),
        if(remaining != [],
          do: "Remaining tasks:\n#{Enum.join(remaining, "\n")}",
          else: nil
        ),
        if(git_log != "", do: git_log, else: nil),
        if(diff_stat != "", do: diff_stat, else: nil)
      ]
      |> Enum.reject(&is_nil/1)

    Apothecary.Worktrees.add_note(worktree_id, Enum.join(parts, "\n"))
  end

  # Private — Crash/kill context for recovery

  defp add_crash_context(worktree_id, agent, reason_line, output) do
    # Capture more output (100 lines) for better crash recovery
    last_output = output |> Enum.take(-100) |> Enum.join("\n")

    # Find in-progress tasks with their titles for richer context
    tasks = Apothecary.Worktrees.list_tasks(worktree_id: worktree_id)

    in_progress =
      tasks
      |> Enum.filter(&(&1.status == "in_progress"))
      |> Enum.map(&"  - #{&1.id}: #{&1.title}")

    in_progress_section =
      if in_progress != [] do
        "\nIn-progress tasks at time of failure:\n#{Enum.join(in_progress, "\n")}"
      else
        ""
      end

    # Include uncommitted changes so the next brewer knows what was mid-flight
    uncommitted =
      if agent.worktree_path do
        case Apothecary.Git.worktree_status(agent.worktree_path) do
          {:ok, status} when status != "" -> "\nUncommitted changes:\n#{status}"
          _ -> ""
        end
      else
        ""
      end

    parts =
      [
        reason_line,
        if(in_progress_section != "", do: in_progress_section, else: nil),
        if(uncommitted != "", do: uncommitted, else: nil),
        if(last_output != "",
          do: "\nLast output (#{min(length(output), 100)} lines):\n#{last_output}",
          else: nil
        )
      ]
      |> Enum.reject(&is_nil/1)

    Apothecary.Worktrees.add_note(worktree_id, Enum.join(parts, "\n"))
  end

  # Private — Worktree finalization

  defp finalize_worktree(worktree_id, agent) do
    project_dir = agent.project_dir
    worktree_path = agent.worktree_path

    # Check if this worktree already has a PR (revision cycle)
    existing_pr_url =
      case Apothecary.Worktrees.get_worktree(worktree_id) do
        {:ok, wt} -> wt.pr_url
        _ -> nil
      end

    # Merge latest main into branch before pushing to catch conflicts early
    merge_result = Apothecary.Git.merge_main_into(project_dir, worktree_path)

    case merge_result do
      :ok ->
        Logger.info("Merged latest main into branch for worktree #{worktree_id}")

      {:error, {:merge_conflict, output}} ->
        # Abort the failed merge so the worktree is clean for a future fix attempt
        Apothecary.Git.abort_merge(worktree_path)
        conflict_files = Apothecary.Git.conflict_files(output)

        Logger.warning("Merge conflict for #{worktree_id} in files: #{inspect(conflict_files)}")

        handle_merge_conflict(worktree_id, conflict_files, output)

      {:error, reason} ->
        Logger.warning("Failed to merge main into branch for #{worktree_id}: #{inspect(reason)}")

        Apothecary.Worktrees.add_note(
          worktree_id,
          "Merge main failed: #{inspect(reason)}. Pushing branch as-is."
        )
    end

    # If we hit a merge conflict, don't proceed to push — the worktree needs user approval
    if match?({:error, {:merge_conflict, _}}, merge_result) do
      :merge_conflict
    else
      push_and_finalize(worktree_id, agent, existing_pr_url)
    end
  end

  defp push_and_finalize(worktree_id, agent, existing_pr_url) do
    worktree_path = agent.worktree_path
    project_dir = agent.project_dir

    # Push the branch
    case Apothecary.Git.push_branch(worktree_path) do
      {:ok, _} ->
        Logger.info("Pushed branch for worktree #{worktree_id}")

        # Check if there are remaining open tasks — if so, stay dispatchable
        # instead of moving to brew_done (which would briefly flash in reviewing
        # before being re-claimed by the dispatcher)
        has_remaining_tasks =
          Apothecary.Worktrees.list_tasks(worktree_id: worktree_id, status: "open")
          |> Enum.any?()

        if has_remaining_tasks do
          Apothecary.Worktrees.add_note(
            worktree_id,
            "Branch pushed with completed work. Remaining tasks will be picked up next."
          )

          Apothecary.Worktrees.update_worktree(worktree_id, %{
            status: "open",
            assigned_brewer_id: nil
          })
        else
          cond do
            existing_pr_url ->
              # Revision cycle — PR already exists, just push and go back to pr_open
              Apothecary.Worktrees.add_note(
                worktree_id,
                "Revision pushed to existing PR: #{existing_pr_url}"
              )

              Apothecary.Worktrees.update_worktree(worktree_id, %{
                status: "pr_open",
                assigned_brewer_id: nil
              })

            Apothecary.Git.auto_pr?() ->
              # Auto PR: create PR and set to pr_open
              pr_result = create_pr_with_retry(worktree_id, worktree_path, project_dir)

              case pr_result do
                {:ok, _pr_url} ->
                  Apothecary.Worktrees.update_worktree(worktree_id, %{
                    status: "pr_open",
                    assigned_brewer_id: nil
                  })

                {:error, reason} ->
                  branch = agent.branch || "(unknown)"

                  Apothecary.Worktrees.add_note(
                    worktree_id,
                    "PR creation failed: #{inspect(reason)}. " <>
                      "Branch '#{branch}' was pushed — create PR manually from dashboard."
                  )

                  Apothecary.Worktrees.update_worktree(worktree_id, %{
                    status: "brew_done",
                    assigned_brewer_id: nil
                  })
              end

            true ->
              # Manual: branch pushed, waiting for user to create PR from dashboard
              Apothecary.Worktrees.add_note(
                worktree_id,
                "Branch pushed. Create PR from the dashboard when ready."
              )

              Apothecary.Worktrees.update_worktree(worktree_id, %{
                status: "brew_done",
                assigned_brewer_id: nil
              })
          end
        end

      {:error, reason} ->
        Logger.warning("Failed to push branch for worktree #{worktree_id}: #{inspect(reason)}")

        Apothecary.Worktrees.add_note(
          worktree_id,
          "Push failed: #{inspect(reason)}. Branch is ready — retry push from the dashboard."
        )

        # Set to brew_done so the worktree appears in the reviewing lane
        # for manual retry, instead of staying stuck in "in_progress"
        Apothecary.Worktrees.update_worktree(worktree_id, %{
          status: "brew_done",
          assigned_brewer_id: nil
        })
    end
  end

  defp handle_merge_conflict(worktree_id, conflict_files, _output) do
    files_list =
      case conflict_files do
        [] -> "unknown files"
        files -> Enum.join(files, ", ")
      end

    Apothecary.Worktrees.add_note(
      worktree_id,
      "⚠ Merge conflict with main in: #{files_list}.\n" <>
        "Auto-dispatching a brewer to resolve conflicts."
    )

    # Create a fix-merge-conflicts task — auto-dispatched (not blocked)
    Apothecary.Worktrees.create_task(%{
      worktree_id: worktree_id,
      title: "Fix merge conflicts with main",
      priority: 0,
      description:
        "⚠ AUTO-FIX: Merge conflicts detected when merging main into this branch.\n" <>
          "Conflicting files: #{files_list}\n\n" <>
          "Steps to resolve:\n" <>
          "1. Run `git merge origin/main --no-edit` to reproduce the conflicts\n" <>
          "2. Resolve conflicts in the affected files\n" <>
          "3. `git add` the resolved files and `git commit` to complete the merge\n\n" <>
          "After resolving, add a note: 'Merge conflicts automatically resolved in: #{files_list}'",
      status: "open"
    })

    # Set worktree back to open so it gets dispatched automatically
    Apothecary.Worktrees.update_worktree(worktree_id, %{
      status: "open",
      assigned_brewer_id: nil
    })
  end

  defp create_pr_with_retry(worktree_id, worktree_path, project_dir, retries \\ 2) do
    case Apothecary.Worktrees.get_worktree(worktree_id) do
      {:ok, worktree} ->
        title = "[#{worktree_id}] #{worktree.title}"
        do_create_pr(worktree_id, worktree_path, project_dir, title, retries)

      {:error, _} ->
        {:error, :worktree_not_found}
    end
  end

  defp do_create_pr(worktree_id, worktree_path, project_dir, title, retries_left) do
    case Apothecary.Git.create_pr(project_dir, worktree_path, title) do
      {:ok, pr_url} ->
        Logger.info("Created PR for worktree #{worktree_id}: #{pr_url}")

        Apothecary.Worktrees.update_worktree(worktree_id, %{
          pr_url: pr_url
        })

        Apothecary.Worktrees.add_note(worktree_id, "PR created: #{pr_url}")
        {:ok, pr_url}

      {:error, reason} when retries_left > 0 ->
        Logger.warning(
          "PR creation attempt failed for #{worktree_id}: #{inspect(reason)}, " <>
            "#{retries_left} retries left"
        )

        Process.sleep(2_000)
        do_create_pr(worktree_id, worktree_path, project_dir, title, retries_left - 1)

      {:error, reason} ->
        Logger.warning("Failed to create PR for worktree #{worktree_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private — MCP config

  defp write_mcp_config(worktree_path, agent_id, worktree_id, extra_mcps, project_dir) do
    config =
      Apothecary.McpConfig.build(agent_id, worktree_id,
        extra_mcps: extra_mcps,
        project_dir: project_dir
      )

    merged = config["mcpServers"]

    mcp_path = Path.join(worktree_path, ".mcp.json")

    case File.write(mcp_path, Jason.encode!(config, pretty: true)) do
      :ok ->
        extra_count = map_size(merged) - 1

        if extra_count > 0 do
          extra_names = merged |> Map.keys() |> List.delete("apothecary") |> Enum.join(", ")
          Logger.info("MCP config: apothecary + #{extra_count} passthrough(s): #{extra_names}")
        end

        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to write MCP config to #{mcp_path}: #{inspect(reason)}. " <>
            "Brewer will run without MCP tools."
        )
    end
  end

  defp write_claude_md(worktree_path) do
    claude_dir = Path.join(worktree_path, ".claude")
    File.mkdir_p!(claude_dir)

    claude_md_path = Path.join(claude_dir, "CLAUDE.md")

    case File.write(claude_md_path, Apothecary.Startup.default_claude_md()) do
      :ok ->
        Logger.info("Wrote apothecary CLAUDE.md to #{claude_md_path}")

      {:error, reason} ->
        Logger.warning(
          "Failed to write CLAUDE.md to #{claude_md_path}: #{inspect(reason)}. " <>
            "Brewer will still receive instructions via prompt."
        )
    end
  end

  # Private — Claude process

  defp spawn_claude(agent, worktree, tasks) do
    claude_path = Application.get_env(:apothecary, :claude_path, "claude")
    claude_exe = System.find_executable(claude_path)

    unless claude_exe do
      {:error, "Claude Code executable not found: #{claude_path}"}
    else
      prompt =
        if worktree.kind == "question",
          do: build_question_prompt(worktree, agent.worktree_path),
          else: build_prompt(worktree, tasks, agent.worktree_path)

      Logger.info(
        "Brewer #{agent.id} spawning claude (#{byte_size(prompt)} byte prompt) " <>
          "in #{agent.worktree_path}"
      )

      try do
        script_exe = System.find_executable("script")

        claude_cmd =
          "'#{claude_exe}' -p \"$APOTHECARY_PROMPT\" " <>
            "--dangerously-skip-permissions --verbose --output-format stream-json"

        {cmd, sandboxed} =
          maybe_sandbox_wrap(claude_cmd, agent.worktree_path, agent.project_dir, agent.id)

        {executable, args} =
          if script_exe do
            Logger.info("Brewer #{agent.id} using PTY wrapper (script)")

            case :os.type() do
              {:unix, :darwin} ->
                {script_exe, ["-q", "/dev/null", "/bin/sh", "-c", cmd]}

              _ ->
                {script_exe, ["-qfec", cmd, "/dev/null"]}
            end
          else
            Logger.info("Brewer #{agent.id} using direct sh (no PTY)")
            sh = System.find_executable("sh") || "/bin/sh"
            {sh, ["-c", cmd]}
          end

        port =
          Port.open({:spawn_executable, executable}, [
            :binary,
            :exit_status,
            :use_stdio,
            {:args, args},
            {:env, [{~c"APOTHECARY_PROMPT", String.to_charlist(prompt)}]},
            {:cd, to_charlist(agent.worktree_path)}
          ])

        Process.send_after(self(), {:accept_permissions, port}, 1_000)

        {:ok, port, sandboxed}
      rescue
        e ->
          {:error, Exception.message(e)}
      end
    end
  end

  defp build_question_prompt(worktree, project_dir) do
    project_digest =
      if project_dir, do: Apothecary.ProjectDigest.generate(project_dir), else: ""

    """
    You are a codebase expert answering a question about the project in: #{project_dir}

    ## Question
    #{worktree.title}
    #{if worktree.description && worktree.description != worktree.title, do: "\n#{worktree.description}", else: ""}

    ## Project Structure
    #{project_digest}

    ## Rules
    - This is a READ-ONLY inquiry. Do NOT modify any files.
    - Do NOT create commits, branches, or PRs.
    - Do NOT run destructive commands.
    - Answer the question thoroughly by reading relevant source files.
    - Be concise but complete. Use code references (file:line) where helpful.
    """
  end

  defp build_prompt(worktree, tasks, worktree_path) do
    project_dir = worktree.project_id && lookup_project_dir(worktree.project_id)

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

    task_list = format_task_list(tasks)

    notes_section =
      if worktree.notes && worktree.notes != "" do
        """
        ## Context & Notes
        #{worktree.notes}
        """
      else
        ""
      end

    revision_section =
      if worktree.pr_url do
        """
        ## PR Revision
        This worktree has an existing PR: #{worktree.pr_url}
        You have been re-dispatched to address review feedback.
        Check the PR comments with `gh pr view #{worktree.pr_url} --comments` and address any requested changes.
        Do NOT create a new PR — just commit your fixes and the orchestrator will push to the existing PR branch.
        """
      else
        ""
      end

    git_context = build_git_context(project_dir, worktree_path)

    # Generate project structure digest so brewers don't need to explore from scratch
    project_digest =
      if project_dir, do: Apothecary.ProjectDigest.generate(project_dir), else: ""

    """
    You are an autonomous coding agent working in: #{worktree_path}

    ## Your Work
    Worktree ID: #{worktree.id}
    Title: #{worktree.title}
    Description: #{worktree.description || worktree.title}

    ## Project Structure
    #{project_digest}

    #{notes_section}
    #{git_context}
    #{revision_section}
    ## Task Management via MCP
    You have MCP tools to manage tasks within this worktree:
    - **worktree_status** — See your worktree overview and all tasks
    - **list_tasks** — List tasks (with optional status filter)
    - **create_task** — Create a sub-task (for decomposing complex work)
    - **complete_task** — Mark a task as done
    - **add_notes** — Log progress notes (persists across restarts)
    - **get_task** — Get full details of a task
    - **add_dependency** — Wire dependencies between tasks

    #{if task_list != "" do
      """
      ## Pre-Created Tasks
      #{task_list}

      Work through each task in order. Use `complete_task` to mark each done.
      """
    else
      """
      ## Instructions
      Assess the complexity of this work:

      **If the task is small and self-contained:**
      1. Implement it directly
      2. Run tests to verify
      3. Use `complete_task` or `add_notes` to report what you did
      4. Commit your changes

      **If the task is complex (touches multiple files/systems):**
      1. Use `create_task` to decompose into ordered sub-tasks
      2. Use `add_dependency` to wire blocking relationships if needed
      3. Work through each sub-task, using `complete_task` as you go
      4. Commit after each logical piece of work
      5. Run tests to verify everything works together
      """
    end}

    **IMPORTANT:** Before starting work, call `worktree_status` to get the latest task list and notes.
    Tasks may have been added or updated since this prompt was generated.

    ## Rules
    - You are on a feature branch in a git worktree, NOT main
    - NEVER push to main or merge into main
    - Commit when done with each piece of work
    - The orchestrator will handle pushing, PR creation, and closing
    - Do NOT push — the orchestrator handles that

    ## Context Survival ("Land the Plane")
    Your session may be interrupted at any time (crash, timeout, OOM). To help the next brewer recover quickly:
    - **Log progress frequently**: Call `add_notes` after each significant milestone, decision, or discovery
    - **Be structured**: Include what you tried, what worked/didn't, and what's next
    - **Before finishing**: Write a final summary note with `add_notes` covering what was accomplished and any remaining work
    - **Commit early, commit often**: Each commit is a recovery checkpoint — uncommitted work may be lost
    - Notes and git history are the primary way the next brewer rebuilds context if you crash

    #{if claude_md != "", do: "## Project Guidelines (CLAUDE.md)\n#{claude_md}", else: ""}
    #{if agents_md != "", do: "## Agent Guidelines (AGENTS.md)\n#{agents_md}", else: ""}
    """
  end

  defp build_git_context(nil, _worktree_path), do: ""

  defp build_git_context(project_dir, worktree_path) do
    # Use log with stats so brewers see which files each commit touched
    log_section =
      case Apothecary.Git.worktree_log_with_stats(project_dir, worktree_path, 10) do
        {:ok, log} when log != "" ->
          "### Commits on this branch (with files changed)\n```\n#{log}\n```"

        _ ->
          # Fallback to plain log
          case Apothecary.Git.worktree_log(project_dir, worktree_path) do
            {:ok, log} when log != "" ->
              "### Commits on this branch\n```\n#{log}\n```"

            _ ->
              nil
          end
      end

    # Overall branch diff stat (total files changed, insertions, deletions)
    diff_stat_section =
      case Apothecary.Git.worktree_diff_stat(project_dir, worktree_path) do
        {:ok, stat} when stat != "" ->
          "### Branch diff summary (vs main)\n```\n#{stat}\n```"

        _ ->
          nil
      end

    uncommitted_section =
      case Apothecary.Git.worktree_status(worktree_path) do
        {:ok, status} when status != "" ->
          "### Uncommitted changes\n```\n#{status}\n```"

        _ ->
          nil
      end

    sections = Enum.reject([log_section, diff_stat_section, uncommitted_section], &is_nil/1)

    if sections == [] do
      ""
    else
      "## Git Context (prior work on this branch)\n" <> Enum.join(sections, "\n\n")
    end
  end

  defp format_task_list([]), do: ""

  defp format_task_list(tasks) do
    tasks
    |> Enum.sort_by(fn t -> {t.priority || 99, t.created_at || ""} end)
    |> Enum.map(fn t ->
      status = if t.status == "done", do: "x", else: " "

      blockers =
        if t.blockers != [], do: " (blocked by: #{Enum.join(t.blockers, ", ")})", else: ""

      line = "- [#{status}] #{t.id}: #{t.title}#{blockers}"

      if t.notes && t.notes != "" do
        line <> "\n  Notes: #{t.notes}"
      else
        line
      end
    end)
    |> Enum.join("\n")
  end

  defp parse_stream_line(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "assistant", "message" => %{"content" => content}}} ->
        extract_text_from_content(content)

      {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
        [text]

      {:ok, %{"type" => "result", "result" => result}} ->
        [result]

      {:ok, %{"type" => "tool_use", "tool" => tool}} ->
        ["[tool: #{tool}]"]

      {:ok, %{"type" => "tool_result"}} ->
        []

      {:ok, %{"type" => "system"}} ->
        []

      {:ok, _event} ->
        []

      {:error, _} ->
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

  defp flush_buffer(""), do: []

  defp flush_buffer(buffer) do
    buffer
    |> strip_ansi()
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse_stream_line/1)
  end

  defp strip_ansi(text) do
    text
    |> String.replace(~r/\e\[\??[0-9;]*[a-zA-Z]/, "")
    |> String.replace(~r/\e\([A-Z]/, "")
    |> String.replace("\r", "")
  end

  # Watchdog — kills stuck brewers

  defp schedule_watchdog do
    Process.send_after(self(), :watchdog, @stuck_timeout_ms)
  end

  defp reset_watchdog(state) do
    cancel_watchdog(state)
    %{state | watchdog_timer: schedule_watchdog()}
  end

  defp cancel_watchdog(%{watchdog_timer: nil}), do: :ok
  defp cancel_watchdog(%{watchdog_timer: timer}), do: Process.cancel_timer(timer)

  defp schedule_error_reset do
    Process.send_after(self(), :reset_after_error, @error_display_time)
  end

  defp broadcast_state(agent) do
    Phoenix.PubSub.broadcast(@pubsub, "brewer:#{agent.id}", {:agent_state, agent})
    report_state(agent)
  end

  defp broadcast_output(agent_id, lines) do
    Phoenix.PubSub.broadcast(@pubsub, "brewer:#{agent_id}", {:agent_output, agent_id, lines})
  end

  defp report_state(agent) do
    GenServer.cast(Apothecary.Dispatcher, {:agent_update, self(), agent})
  end

  defp lookup_project_dir(project_id) do
    case Apothecary.Projects.get(project_id) do
      {:ok, project} -> project.path
      _ -> nil
    end
  end

  # Sandbox — OS-level filesystem restriction to worktree

  defp maybe_sandbox_wrap(cmd, worktree_path, project_dir, agent_id) do
    case :os.type() do
      {:unix, :darwin} -> sandbox_wrap_darwin(cmd, worktree_path, project_dir, agent_id)
      {:unix, _} -> sandbox_wrap_linux(cmd, worktree_path, project_dir, agent_id)
      _ -> {cmd, false}
    end
  end

  defp sandbox_wrap_darwin(cmd, worktree_path, project_dir, agent_id) do
    sandbox_exec = System.find_executable("sandbox-exec")

    if sandbox_exec do
      profile = generate_seatbelt_profile(worktree_path, project_dir)
      profile_path = sandbox_profile_path(agent_id)
      File.write!(profile_path, profile)

      Logger.info(
        "Brewer #{agent_id} sandboxed via sandbox-exec (writes restricted to #{worktree_path})"
      )

      {"'#{sandbox_exec}' -f '#{profile_path}' /bin/sh -c #{escape_for_sh(cmd)}", true}
    else
      Logger.warning("Brewer #{agent_id} sandbox-exec not found, running unsandboxed")
      {cmd, false}
    end
  end

  defp sandbox_wrap_linux(cmd, worktree_path, project_dir, agent_id) do
    bwrap = System.find_executable("bwrap")

    if bwrap do
      home = System.get_env("HOME") || "/root"
      claude_dir = Path.join(home, ".claude")
      git_dir = if project_dir, do: Path.join(project_dir, ".git"), else: nil

      Logger.info(
        "Brewer #{agent_id} sandboxed via bwrap (writes restricted to #{worktree_path})"
      )

      git_bind = if git_dir, do: "--bind '#{git_dir}' '#{git_dir}' ", else: ""

      wrapped =
        "'#{bwrap}' " <>
          "--unshare-all " <>
          "--share-net " <>
          "--die-with-parent " <>
          "--ro-bind / / " <>
          "--proc /proc " <>
          "--dev /dev " <>
          "--bind '#{worktree_path}' '#{worktree_path}' " <>
          git_bind <>
          "--bind '#{claude_dir}' '#{claude_dir}' " <>
          "--bind /tmp /tmp " <>
          "-- /bin/sh -c #{escape_for_sh(cmd)}"

      {wrapped, true}
    else
      Logger.warning(
        "Brewer #{agent_id} bwrap not found, running unsandboxed (install bubblewrap for sandbox support)"
      )

      {cmd, false}
    end
  end

  defp generate_seatbelt_profile(worktree_path, project_dir) do
    home = System.get_env("HOME") || "/Users/#{System.get_env("USER")}"
    claude_dir = Path.join(home, ".claude")

    # Git worktrees store internal state in <main-repo>/.git/worktrees/
    # so we must allow writes there for commits to work
    git_dir_rule =
      if project_dir do
        git_dir = Path.join(project_dir, ".git")
        ~s|        (require-not (subpath "#{git_dir}"))\n|
      else
        ""
      end

    """
    (version 1)
    (allow default)

    ; Restrict file writes to worktree and necessary system paths
    (deny file-write*
      (require-all
        (require-not (subpath "#{worktree_path}"))
    #{git_dir_rule}        (require-not (subpath "/private/tmp"))
        (require-not (subpath "/tmp"))
        (require-not (subpath "/private/var/folders"))
        (require-not (subpath "#{claude_dir}"))
        (require-not (literal "/dev/null"))
        (require-not (literal "/dev/tty"))
        (require-not (literal "/dev/urandom"))
      )
    )
    """
  end

  defp sandbox_profile_path(agent_id) do
    Path.join(System.tmp_dir!(), "apothecary-sandbox-#{agent_id}.sb")
  end

  defp cleanup_sandbox_profile(agent_id) do
    path = sandbox_profile_path(agent_id)
    File.rm(path)
  end

  defp escape_for_sh(cmd) do
    # Wrap the command in single quotes for the outer sh -c,
    # escaping any single quotes within
    "'" <> String.replace(cmd, "'", "'\\''") <> "'"
  end
end
