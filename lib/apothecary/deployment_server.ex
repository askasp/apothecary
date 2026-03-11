defmodule Apothecary.DeploymentServer do
  @moduledoc """
  GenServer managing deployment OS processes.

  Follows DevServer's Erlang Port pattern but with Mnesia persistence
  and Caddy integration. On Apothecary restart, re-spawns all deployments
  that were marked as "running" in Mnesia.
  """

  use GenServer
  require Logger

  alias Apothecary.{CaddyManager, Deployment, Deployments, DevConfig, PortProcess, Projects}

  @pubsub Apothecary.PubSub
  @topic "deployment_servers:updates"
  @max_output_lines 100
  @health_check_interval_ms 500
  @health_check_max_attempts 240
  @shutdown_timeout_ms 10_000

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @doc "Start a deployment process."
  def start_deployment(deployment_id) do
    GenServer.call(__MODULE__, {:start, deployment_id}, 60_000)
  end

  @doc "Stop a deployment process."
  def stop_deployment(deployment_id) do
    GenServer.call(__MODULE__, {:stop, deployment_id}, 15_000)
  end

  @doc "Rebuild a deployment (git pull -> stop -> setup -> start)."
  def rebuild(deployment_id) do
    GenServer.call(__MODULE__, {:rebuild, deployment_id}, 120_000)
  end

  @doc "Rebuild all deployments tracking a given branch for a project."
  def rebuild_for_branch(project_id, branch) do
    GenServer.cast(__MODULE__, {:rebuild_for_branch, project_id, branch})
  end

  @doc "Get runtime info for a deployment."
  def get_runtime(deployment_id) do
    GenServer.call(__MODULE__, {:get_runtime, deployment_id})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    state = %{
      processes: %{},
      port_to_dep: %{}
    }

    # Re-spawn deployments that were running before restart
    send(self(), :recover_running)

    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("DeploymentServer shutting down, stopping #{map_size(state.processes)} deployment(s)")

    for {_dep_id, %{port: port}} when not is_nil(port) <- state.processes do
      try do
        Port.close(port)
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  @impl true
  def handle_call({:start, deployment_id}, _from, state) do
    case Map.get(state.processes, deployment_id) do
      %{status: status} when status in [:starting, :running] ->
        {:reply, {:error, :already_running}, state}

      _ ->
        case do_start(deployment_id, state) do
          {:ok, state} -> {:reply, :ok, state}
          {:error, reason, state} -> {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:stop, deployment_id}, _from, state) do
    state = do_stop(deployment_id, state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:rebuild, deployment_id}, _from, state) do
    state = do_stop(deployment_id, state)

    case Deployments.get(deployment_id) do
      {:ok, dep} ->
        # Pull latest for the branch
        working_dir = deploy_worktree_dir(dep)

        if File.dir?(working_dir) do
          case Apothecary.CLI.run("git", ["-C", working_dir, "pull", "--ff-only"]) do
            {:ok, _} -> :ok
            {:error, reason} -> Logger.warning("Git pull failed for #{deployment_id}: #{inspect(reason)}")
          end
        end

        case do_start(deployment_id, state) do
          {:ok, state} -> {:reply, :ok, state}
          {:error, reason, state} -> {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_runtime, deployment_id}, _from, state) do
    case Map.get(state.processes, deployment_id) do
      nil -> {:reply, nil, state}
      info -> {:reply, Map.take(info, [:status, :output, :error]), state}
    end
  end

  @impl true
  def handle_cast({:rebuild_for_branch, project_id, branch}, state) do
    deployments = Deployments.list(project_id)

    matching =
      Enum.filter(deployments, fn dep ->
        dep.branch == branch and dep.status in ["running", "starting"]
      end)

    state =
      Enum.reduce(matching, state, fn dep, acc ->
        acc = do_stop(dep.id, acc)

        working_dir = deploy_worktree_dir(dep)

        if File.dir?(working_dir) do
          case Apothecary.CLI.run("git", ["-C", working_dir, "pull", "--ff-only"]) do
            {:ok, _} -> :ok
            {:error, reason} -> Logger.warning("Git pull failed for #{dep.id}: #{inspect(reason)}")
          end
        end

        case do_start(dep.id, acc) do
          {:ok, acc} -> acc
          {:error, _reason, acc} -> acc
        end
      end)

    {:noreply, state}
  end

  # Port data
  @impl true
  def handle_info({port, {:data, data}}, state) when is_port(port) do
    case Map.get(state.port_to_dep, port) do
      nil ->
        {:noreply, state}

      dep_id ->
        process = state.processes[dep_id]

        if process do
          lines = data |> to_string() |> String.split("\n", trim: true)
          output = (process.output ++ lines) |> Enum.take(-@max_output_lines)
          process = %{process | output: output}
          state = put_in(state.processes[dep_id], process)
          broadcast_update(dep_id, process)
          {:noreply, state}
        else
          {:noreply, state}
        end
    end
  end

  # Port exited normally
  @impl true
  def handle_info({port, {:exit_status, 0}}, state) when is_port(port) do
    case Map.get(state.port_to_dep, port) do
      nil ->
        {:noreply, state}

      dep_id ->
        Logger.info("Deployment #{dep_id} process exited normally")
        Deployments.update_status(dep_id, "stopped")
        remove_caddy_routes(dep_id)
        state = cleanup_process(dep_id, state)
        {:noreply, state}
    end
  end

  # Port exited with error
  @impl true
  def handle_info({port, {:exit_status, code}}, state) when is_port(port) do
    case Map.get(state.port_to_dep, port) do
      nil ->
        {:noreply, state}

      dep_id ->
        Logger.warning("Deployment #{dep_id} process exited with code #{code}")
        process = state.processes[dep_id]

        if process do
          error_msg = PortProcess.diagnose_error(code, process.output, 0)
          Deployments.update_status(dep_id, "error", error: error_msg)
          remove_caddy_routes(dep_id)

          process = %{process | status: :error, error: error_msg, port: nil}
          state = put_in(state.processes[dep_id], process)
          state = release_port_mapping(state, port)
          broadcast_update(dep_id, process)
          {:noreply, state}
        else
          {:noreply, state}
        end
    end
  end

  # Health check
  @impl true
  def handle_info({:health_check, dep_id, port, attempt}, state) do
    case Map.get(state.processes, dep_id) do
      %{status: :starting} = process ->
        if PortProcess.tcp_port_open?(port) do
          Logger.info("Deployment #{dep_id} is ready on port #{port}")
          Deployments.update_status(dep_id, "running")
          add_caddy_routes(dep_id)

          process = %{process | status: :running}
          state = put_in(state.processes[dep_id], process)
          broadcast_update(dep_id, process)
          {:noreply, state}
        else
          if attempt < @health_check_max_attempts do
            Process.send_after(self(), {:health_check, dep_id, port, attempt + 1}, @health_check_interval_ms)
            {:noreply, state}
          else
            Logger.warning("Deployment #{dep_id} health check timed out, marking running anyway")
            Deployments.update_status(dep_id, "running")
            add_caddy_routes(dep_id)

            process = %{process | status: :running}
            state = put_in(state.processes[dep_id], process)
            broadcast_update(dep_id, process)
            {:noreply, state}
          end
        end

      _ ->
        {:noreply, state}
    end
  end

  # Shutdown timeout
  @impl true
  def handle_info({:shutdown_timeout, dep_id}, state) do
    case Map.get(state.processes, dep_id) do
      %{port: port} when not is_nil(port) ->
        Logger.warning("Deployment #{dep_id} didn't stop gracefully, force closing port")

        try do
          Port.close(port)
        rescue
          _ -> :ok
        end

        state = cleanup_process(dep_id, state)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  # Recovery on startup
  @impl true
  def handle_info(:recover_running, state) do
    running = Deployments.list_by_status("running")

    state =
      Enum.reduce(running, state, fn dep, acc ->
        Logger.info("Recovering deployment #{dep.id} (#{dep.name})")

        case do_start(dep.id, acc) do
          {:ok, acc} -> acc
          {:error, reason, acc} ->
            Logger.error("Failed to recover deployment #{dep.id}: #{inspect(reason)}")
            acc
        end
      end)

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("DeploymentServer received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # --- Private ---

  defp do_start(deployment_id, state) do
    case Deployments.get(deployment_id) do
      {:ok, dep} ->
        # Check Caddy availability
        unless CaddyManager.available?() do
          Logger.warning("Caddy not available — deployment #{deployment_id} will run without public URL")
        end

        working_dir = ensure_working_dir(dep)

        case working_dir do
          {:ok, dir} ->
            # Load preview.yml from working dir
            case DevConfig.load(dir) do
              {:ok, config} ->
                Deployments.update_status(deployment_id, "starting")

                # Build env
                host = resolve_host(dep)

                env =
                  System.get_env()
                  |> Map.put("BASE_PORT", to_string(dep.base_port))
                  |> Map.put("SECRET_KEY_BASE", dep.secret_key_base)
                  |> Map.put("HOST", host)
                  |> Map.put("PHX_HOST", host)
                  |> Map.merge(dep.env_vars)
                  |> Enum.to_list()

                # Run setup
                case PortProcess.run_setup(config.setup, dir, env) do
                  :ok ->
                    case PortProcess.spawn_command(config.command, dir, env) do
                      {:ok, port} ->
                        process = %{
                          port: port,
                          status: :starting,
                          output: [],
                          error: nil,
                          config: config,
                          working_dir: dir
                        }

                        state = put_in(state.processes[deployment_id], process)
                        state = %{state | port_to_dep: Map.put(state.port_to_dep, port, deployment_id)}
                        broadcast_update(deployment_id, process)

                        Process.send_after(
                          self(),
                          {:health_check, deployment_id, dep.base_port, 0},
                          @health_check_interval_ms
                        )

                        {:ok, state}

                      {:error, reason} ->
                        Deployments.update_status(deployment_id, "error",
                          error: "Failed to spawn: #{inspect(reason)}"
                        )

                        {:error, reason, state}
                    end

                  {:error, reason} ->
                    Deployments.update_status(deployment_id, "error",
                      error: "Setup failed: #{reason}"
                    )

                    {:error, {:setup_failed, reason}, state}
                end

              :not_found ->
                # Try auto-detection
                case DevConfig.detect(dir) do
                  {:ok, config} ->
                    # Retry with detected config — write it to disk for next time
                    do_start_with_config(deployment_id, dep, dir, config, state)

                  :not_detected ->
                    Deployments.update_status(deployment_id, "error",
                      error: "No .apothecary/preview.yml found and could not auto-detect config"
                    )

                    {:error, :no_dev_config, state}
                end

              {:error, reason} ->
                Deployments.update_status(deployment_id, "error",
                  error: "Config error: #{reason}"
                )

                {:error, {:config_error, reason}, state}
            end

          {:error, reason} ->
            Deployments.update_status(deployment_id, "error",
              error: "Working directory error: #{inspect(reason)}"
            )

            {:error, reason, state}
        end

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp do_start_with_config(deployment_id, dep, dir, config, state) do
    Deployments.update_status(deployment_id, "starting")

    host = resolve_host(dep)

    env =
      System.get_env()
      |> Map.put("BASE_PORT", to_string(dep.base_port))
      |> Map.put("SECRET_KEY_BASE", dep.secret_key_base)
      |> Map.put("HOST", host)
      |> Map.put("PHX_HOST", host)
      |> Map.merge(dep.env_vars)
      |> Enum.to_list()

    case PortProcess.run_setup(config.setup, dir, env) do
      :ok ->
        case PortProcess.spawn_command(config.command, dir, env) do
          {:ok, port} ->
            process = %{
              port: port,
              status: :starting,
              output: [],
              error: nil,
              config: config,
              working_dir: dir
            }

            state = put_in(state.processes[deployment_id], process)
            state = %{state | port_to_dep: Map.put(state.port_to_dep, port, deployment_id)}
            broadcast_update(deployment_id, process)

            Process.send_after(
              self(),
              {:health_check, deployment_id, dep.base_port, 0},
              @health_check_interval_ms
            )

            {:ok, state}

          {:error, reason} ->
            Deployments.update_status(deployment_id, "error",
              error: "Failed to spawn: #{inspect(reason)}"
            )

            {:error, reason, state}
        end

      {:error, reason} ->
        Deployments.update_status(deployment_id, "error",
          error: "Setup failed: #{reason}"
        )

        {:error, {:setup_failed, reason}, state}
    end
  end

  defp do_stop(deployment_id, state) do
    case Map.get(state.processes, deployment_id) do
      nil ->
        Deployments.update_status(deployment_id, "stopped")
        state

      %{port: nil} ->
        Deployments.update_status(deployment_id, "stopped")
        remove_caddy_routes(deployment_id)
        cleanup_process(deployment_id, state)

      %{port: port, config: config, working_dir: dir} ->
        # Run shutdown command if defined
        if config && config.shutdown do
          env = System.get_env() |> Enum.to_list()

          Elixir.Task.start(fn ->
            try do
              System.cmd("sh", ["-c", config.shutdown], cd: dir, env: env, stderr_to_stdout: true)
            rescue
              _ -> :ok
            end
          end)
        end

        Process.send_after(self(), {:shutdown_timeout, deployment_id}, @shutdown_timeout_ms)

        try do
          Port.close(port)
        rescue
          _ -> :ok
        end

        Deployments.update_status(deployment_id, "stopped")
        remove_caddy_routes(deployment_id)
        state = cleanup_process(deployment_id, state)
        broadcast_update(deployment_id, %{status: :stopped, output: [], error: nil})
        state
    end
  end

  defp ensure_working_dir(dep) do
    dir = deploy_worktree_dir(dep)

    if File.dir?(dir) do
      # Update to correct branch
      case Apothecary.CLI.run("git", ["-C", dir, "checkout", dep.branch]) do
        {:ok, _} -> {:ok, dir}
        {:error, reason} -> Logger.warning("Branch checkout failed: #{inspect(reason)}")
      end

      case Apothecary.CLI.run("git", ["-C", dir, "pull", "--ff-only"]) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end

      {:ok, dir}
    else
      # Create a new worktree for the deployment
      case Projects.get(dep.project_id) do
        {:ok, project} ->
          File.mkdir_p!(Path.dirname(dir))

          case Apothecary.Git.create_worktree(project.path, dir, "deploy/#{dep.id}", dep.branch) do
            {:ok, _} -> {:ok, dir}
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp deploy_worktree_dir(dep) do
    base =
      case Projects.get(dep.project_id) do
        {:ok, project} ->
          expanded = Path.expand(project.path)
          hash = :crypto.hash(:sha256, expanded) |> Base.encode16(case: :lower) |> binary_part(0, 8)
          "#{Path.basename(expanded)}-#{hash}"

        _ ->
          dep.project_id
      end

    Path.join([System.user_home!(), ".apothecary", "deploy-worktrees", base, dep.id])
  end

  defp cleanup_process(dep_id, state) do
    case Map.pop(state.processes, dep_id) do
      {nil, _} ->
        state

      {process, processes} ->
        state = %{state | processes: processes}

        if process.port do
          release_port_mapping(state, process.port)
        else
          state
        end
    end
  end

  defp release_port_mapping(state, port) do
    %{state | port_to_dep: Map.delete(state.port_to_dep, port)}
  end

  defp add_caddy_routes(deployment_id) do
    case Deployments.get(deployment_id) do
      {:ok, dep} ->
        hostname = resolve_host(dep)
        # Primary route: the main hostname → base_port
        CaddyManager.add_route("#{dep.id}-web", hostname, dep.base_port)

        # Additional named port routes if configured
        Enum.each(dep.routes, fn route ->
          port_name = route["port_name"] || route[:port_name] || "web"
          subdomain = route["subdomain"] || route[:subdomain] || ""

          if subdomain != "" do
            sub_hostname = "#{subdomain}.#{hostname}"
            port_offset = port_offset_for(port_name, dep)
            target_port = dep.base_port + port_offset
            CaddyManager.add_route("#{dep.id}-#{port_name}", sub_hostname, target_port)
          end
        end)

      _ ->
        :ok
    end
  end

  defp remove_caddy_routes(deployment_id) do
    case Deployments.get(deployment_id) do
      {:ok, dep} ->
        Enum.each(dep.routes, fn route ->
          port_name = route["port_name"] || route[:port_name] || "web"
          CaddyManager.remove_route("#{dep.id}-#{port_name}")
        end)

      _ ->
        # Deployment already deleted, try removing common route
        CaddyManager.remove_route("#{deployment_id}-web")
    end
  end

  defp resolve_host(dep) do
    slug =
      case Projects.get(dep.project_id) do
        {:ok, project} -> project_slug(project.name)
        _ -> dep.project_id
      end

    Deployment.resolve_hostname(dep, slug)
  end

  defp project_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  defp port_offset_for(port_name, deployment) do
    case Enum.find_index(deployment.routes, fn r ->
           (r["port_name"] || r[:port_name]) == port_name
         end) do
      nil -> 0
      idx -> idx
    end
  end

  defp broadcast_update(dep_id, process) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:deployment_server_update, %{
      deployment_id: dep_id,
      status: process.status,
      output: process[:output] || [],
      error: process[:error]
    }})
  end
end
