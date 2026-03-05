defmodule Apothecary.DevServer do
  @moduledoc """
  GenServer managing dev server processes for worktrees.

  Reads `.apothecary/preview.yml` from each worktree, allocates port slots,
  runs setup/command scripts, and tracks process lifecycle. Broadcasts
  status changes via PubSub for dashboard consumption.
  """

  use GenServer
  require Logger

  alias Apothecary.DevConfig

  @pubsub Apothecary.PubSub
  @topic "dev_servers:updates"
  @max_output_lines 50
  @shutdown_timeout_ms 10_000

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @doc "Start a dev server for a worktree."
  def start_server(worktree_id) do
    GenServer.call(__MODULE__, {:start_server, worktree_id}, 30_000)
  end

  @doc "Start a dev server for a project (main repo, not a worktree)."
  def start_project_server(project_id, project_path) do
    GenServer.call(__MODULE__, {:start_project_server, project_id, project_path}, 30_000)
  end

  @doc "Stop a dev server for a worktree."
  def stop_server(worktree_id) do
    GenServer.call(__MODULE__, {:stop_server, worktree_id}, 15_000)
  end

  @doc "Get status of a specific dev server."
  def get_status(worktree_id) do
    GenServer.call(__MODULE__, {:get_status, worktree_id})
  end

  @doc "List all dev servers with their status."
  def list_servers do
    GenServer.call(__MODULE__, :list_servers)
  end

  @doc "Get resolved port info for a worktree's dev server."
  def server_ports(worktree_id) do
    GenServer.call(__MODULE__, {:server_ports, worktree_id})
  end

  @doc "Check if a worktree has a dev config (explicit or auto-detected)."
  def has_config?(worktree_id) do
    GenServer.call(__MODULE__, {:has_config, worktree_id})
  end

  @doc "Check if a path has a dev config (explicit or auto-detected)."
  def has_config_for_path?(path) do
    case DevConfig.load(path) do
      {:ok, _} ->
        true

      :not_found ->
        case DevConfig.detect(path) do
          {:ok, _} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    {:ok,
     %{
       servers: %{},
       used_slots: MapSet.new(),
       port_to_wt: %{}
     }}
  end

  @impl true
  def handle_call({:start_server, worktree_id}, _from, state) do
    case Map.get(state.servers, worktree_id) do
      %{status: status} when status in [:starting, :running] ->
        {:reply, {:error, :already_running}, state}

      _ ->
        case resolve_worktree_path(worktree_id) do
          {:ok, worktree_path, project_dir} ->
            case load_or_detect_config(worktree_path, project_dir) do
              {:ok, config} ->
                {state, result} = do_start_server(worktree_id, worktree_path, config, state)
                {:reply, result, state}

              :not_found ->
                {:reply, {:error, :no_dev_config}, state}

              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:start_project_server, project_id, project_path}, _from, state) do
    case Map.get(state.servers, project_id) do
      %{status: status} when status in [:starting, :running] ->
        {:reply, {:error, :already_running}, state}

      _ ->
        case load_or_detect_config(project_path) do
          {:ok, config} ->
            {state, result} = do_start_server(project_id, project_path, config, state)
            {:reply, result, state}

          :not_found ->
            {:reply, {:error, :no_dev_config}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:stop_server, worktree_id}, _from, state) do
    {state, result} = do_stop_server(worktree_id, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_status, worktree_id}, _from, state) do
    case Map.get(state.servers, worktree_id) do
      nil -> {:reply, nil, state}
      server -> {:reply, server_info(worktree_id, server), state}
    end
  end

  @impl true
  def handle_call(:list_servers, _from, state) do
    result =
      Map.new(state.servers, fn {wt_id, server} ->
        {wt_id, server_info(wt_id, server)}
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:server_ports, worktree_id}, _from, state) do
    case Map.get(state.servers, worktree_id) do
      %{config: config, base_port: base_port} ->
        {:reply, DevConfig.resolve_ports(config, base_port), state}

      _ ->
        {:reply, [], state}
    end
  end

  @impl true
  def handle_call({:has_config, worktree_id}, _from, state) do
    result =
      case resolve_worktree_path(worktree_id) do
        {:ok, path, project_dir} ->
          case load_or_detect_config(path, project_dir) do
            {:ok, _} -> true
            _ -> false
          end

        _ ->
          false
      end

    {:reply, result, state}
  end

  # Port data from dev server process
  @impl true
  def handle_info({port, {:data, data}}, state) when is_port(port) do
    case Map.get(state.port_to_wt, port) do
      nil ->
        {:noreply, state}

      wt_id ->
        server = state.servers[wt_id]

        if server do
          lines = data |> to_string() |> String.split("\n", trim: true)

          output =
            (server.output ++ lines)
            |> Enum.take(-@max_output_lines)

          server = %{server | output: output, status: :running}
          state = put_in(state.servers[wt_id], server)
          broadcast_update(wt_id, server)
          {:noreply, state}
        else
          {:noreply, state}
        end
    end
  end

  # Port exited normally
  @impl true
  def handle_info({port, {:exit_status, 0}}, state) when is_port(port) do
    case Map.get(state.port_to_wt, port) do
      nil ->
        {:noreply, state}

      wt_id ->
        Logger.info("Dev server for #{wt_id} exited normally")
        state = cleanup_server(wt_id, state)
        {:noreply, state}
    end
  end

  # Port exited with error
  @impl true
  def handle_info({port, {:exit_status, code}}, state) when is_port(port) do
    case Map.get(state.port_to_wt, port) do
      nil ->
        {:noreply, state}

      wt_id ->
        Logger.warning("Dev server for #{wt_id} exited with code #{code}")
        server = state.servers[wt_id]

        if server do
          server = %{
            server
            | status: :error,
              error: "Process exited with code #{code}",
              port: nil
          }

          state = put_in(state.servers[wt_id], server)
          state = release_port_mapping(state, port)
          broadcast_update(wt_id, server)
          {:noreply, state}
        else
          {:noreply, state}
        end
    end
  end

  # Shutdown timeout — force kill
  @impl true
  def handle_info({:shutdown_timeout, wt_id}, state) do
    case Map.get(state.servers, wt_id) do
      %{port: port} when not is_nil(port) ->
        Logger.warning("Dev server for #{wt_id} didn't stop gracefully, force closing port")

        try do
          Port.close(port)
        rescue
          _ -> :ok
        end

        state = cleanup_server(wt_id, state)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("DevServer received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # --- Private: Start ---

  defp do_start_server(wt_id, worktree_path, config, state) do
    # Clean up any previous stopped/error entry
    state = cleanup_server(wt_id, state)

    slot = allocate_slot(state.used_slots)
    base_port = config.base_port + slot * config.port_count

    server = %{
      status: :starting,
      port: nil,
      config: config,
      base_port: base_port,
      slot: slot,
      output: [],
      error: nil,
      worktree_path: worktree_path
    }

    state = %{state | used_slots: MapSet.put(state.used_slots, slot)}
    state = put_in(state.servers[wt_id], server)
    broadcast_update(wt_id, server)

    # Build env: BASE_PORT + config env vars
    env =
      [{"BASE_PORT", to_string(base_port)}] ++
        Enum.map(config.env, fn {k, v} -> {k, v} end)

    # Run setup command synchronously (fast, writes .env etc)
    case run_setup(config.setup, worktree_path, env) do
      :ok ->
        # Spawn main command as Erlang Port
        case spawn_command(config.command, worktree_path, env) do
          {:ok, port} ->
            server = %{server | status: :running, port: port}
            state = put_in(state.servers[wt_id], server)
            state = %{state | port_to_wt: Map.put(state.port_to_wt, port, wt_id)}
            broadcast_update(wt_id, server)
            {state, {:ok, base_port}}

          {:error, reason} ->
            server = %{server | status: :error, error: "Failed to spawn: #{inspect(reason)}"}
            state = put_in(state.servers[wt_id], server)
            broadcast_update(wt_id, server)
            {state, {:error, reason}}
        end

      {:error, reason} ->
        server = %{server | status: :error, error: "Setup failed: #{reason}"}
        state = put_in(state.servers[wt_id], server)
        broadcast_update(wt_id, server)
        {state, {:error, {:setup_failed, reason}}}
    end
  end

  defp run_setup(nil, _path, _env), do: :ok
  defp run_setup("", _path, _env), do: :ok

  defp run_setup(setup_cmd, worktree_path, env) do
    Logger.info("DevServer running setup: #{setup_cmd} in #{worktree_path}")

    try do
      case System.cmd("sh", ["-c", setup_cmd],
             cd: worktree_path,
             env: env,
             stderr_to_stdout: true
           ) do
        {_output, 0} -> :ok
        {output, code} -> {:error, "exit code #{code}: #{String.slice(output, 0, 500)}"}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp spawn_command(command, worktree_path, env) do
    sh = System.find_executable("sh") || "/bin/sh"

    charlist_env = Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    try do
      port =
        Port.open({:spawn_executable, sh}, [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout,
          {:args, ["-c", command]},
          {:env, charlist_env},
          {:cd, to_charlist(worktree_path)}
        ])

      {:ok, port}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  # --- Private: Stop ---

  defp do_stop_server(wt_id, state) do
    case Map.get(state.servers, wt_id) do
      nil ->
        {state, :ok}

      %{status: :stopped} ->
        {state, :ok}

      %{port: nil} ->
        state = cleanup_server(wt_id, state)
        {state, :ok}

      %{config: config, worktree_path: worktree_path, port: port} = server ->
        server = %{server | status: :stopped}
        state = put_in(state.servers[wt_id], server)
        broadcast_update(wt_id, server)

        # Build env for shutdown command
        env =
          [{"BASE_PORT", to_string(server.base_port)}] ++
            Enum.map(config.env, fn {k, v} -> {k, v} end)

        # Run shutdown command if defined
        if config.shutdown do
          Logger.info("DevServer running shutdown: #{config.shutdown} for #{wt_id}")

          charlist_env =
            Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

          Elixir.Task.start(fn ->
            try do
              System.cmd("sh", ["-c", config.shutdown],
                cd: worktree_path,
                env: charlist_env,
                stderr_to_stdout: true
              )
            rescue
              _ -> :ok
            end
          end)
        end

        # Schedule force-kill timeout
        Process.send_after(self(), {:shutdown_timeout, wt_id}, @shutdown_timeout_ms)

        # Also try closing the port directly
        try do
          Port.close(port)
        rescue
          _ -> :ok
        end

        state = cleanup_server(wt_id, state)
        {state, :ok}
    end
  end

  # --- Private: Slot allocation ---

  defp allocate_slot(used_slots) do
    # Find lowest available slot
    Stream.iterate(0, &(&1 + 1))
    |> Enum.find(fn slot -> not MapSet.member?(used_slots, slot) end)
  end

  # --- Private: Cleanup ---

  defp cleanup_server(wt_id, state) do
    case Map.pop(state.servers, wt_id) do
      {nil, _} ->
        state

      {server, servers} ->
        state = %{state | servers: servers}

        state =
          if server.port do
            release_port_mapping(state, server.port)
          else
            state
          end

        state = %{state | used_slots: MapSet.delete(state.used_slots, server.slot)}
        broadcast_update(wt_id, %{status: :stopped})
        state
    end
  end

  defp release_port_mapping(state, port) do
    %{state | port_to_wt: Map.delete(state.port_to_wt, port)}
  end

  # --- Private: Helpers ---

  defp load_or_detect_config(path, fallback_path \\ nil) do
    case DevConfig.load(path) do
      {:ok, _} = ok ->
        ok

      :not_found ->
        # If not found in worktree, try the project root (for untracked config files)
        case maybe_load_from_fallback(fallback_path) do
          {:ok, _} = ok ->
            ok

          _ ->
            case DevConfig.detect(path) do
              {:ok, _} = ok -> ok
              :not_detected -> :not_found
            end
        end

      {:error, _} = err ->
        err
    end
  end

  defp maybe_load_from_fallback(nil), do: :not_found

  defp maybe_load_from_fallback(fallback_path) do
    DevConfig.load(fallback_path)
  end

  defp resolve_worktree_path(worktree_id) do
    case Apothecary.WorktreeManager.get_worktree_info(worktree_id) do
      {:ok, %{path: path, project_dir: project_dir}} -> {:ok, path, project_dir}
      {:ok, %{path: path}} -> {:ok, path, nil}
      :not_found -> {:error, :worktree_not_found}
    end
  end

  defp server_info(wt_id, server) do
    ports =
      if server[:config] && server[:base_port] do
        DevConfig.resolve_ports(server.config, server.base_port)
      else
        []
      end

    %{
      worktree_id: wt_id,
      status: server.status,
      base_port: server[:base_port],
      ports: ports,
      output: server[:output] || [],
      error: server[:error]
    }
  end

  defp broadcast_update(wt_id, server) do
    info =
      case server do
        %{config: _} -> server_info(wt_id, server)
        _ -> %{worktree_id: wt_id, status: server.status, ports: [], output: [], error: nil}
      end

    Phoenix.PubSub.broadcast(@pubsub, @topic, {:dev_server_update, info})
  end
end
