defmodule Apothecary.CaddyManager do
  @moduledoc """
  GenServer managing Caddy reverse proxy routes via the admin API at localhost:2019.

  Uses Caddy's per-path REST API to surgically add/remove routes without
  touching existing Caddyfile-managed configuration. Routes are tagged with
  `@id` fields so they can be individually removed.

  Coexists safely with an existing Caddyfile — routes are appended to the
  existing HTTP server, not replaced.
  """

  use GenServer
  require Logger

  @caddy_admin "http://localhost:2019"
  @id_prefix "apothecary-"

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Add a reverse proxy route. Safe to call multiple times (idempotent via @id)."
  def add_route(id, hostname, target_port) do
    GenServer.call(__MODULE__, {:add_route, id, hostname, target_port})
  end

  @doc "Remove a route by ID."
  def remove_route(id) do
    GenServer.call(__MODULE__, {:remove_route, id})
  end

  @doc "List routes managed by Apothecary."
  def list_routes do
    GenServer.call(__MODULE__, :list_routes)
  end

  @doc "Check if Caddy is reachable."
  def available? do
    GenServer.call(__MODULE__, :available?)
  end

  @doc "Raises if Caddy is not available."
  def check_caddy! do
    unless available?() do
      raise "Caddy is not installed or not running. Install Caddy and start the service to use deployments."
    end
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    :inets.start()
    :ssl.start()

    caddy_available = check_caddy_reachable()

    if caddy_available do
      Logger.info("CaddyManager: Caddy admin API reachable at #{@caddy_admin}")
    else
      Logger.error(
        "CaddyManager: Caddy admin API not reachable at #{@caddy_admin}. " <>
          "Deployments will not have public URLs until Caddy is started."
      )
    end

    # Discover which server to add routes to
    server_name =
      if caddy_available do
        discover_server()
      else
        nil
      end

    # Sync routes from running deployments
    routes =
      if caddy_available && server_name do
        sync_from_mnesia(server_name)
      else
        %{}
      end

    {:ok, %{routes: routes, caddy_available: caddy_available, server_name: server_name}}
  end

  @impl true
  def handle_call({:add_route, id, hostname, target_port}, _from, state) do
    if state.caddy_available do
      # Ensure we have a server to add to
      server_name = state.server_name || discover_or_create_server()

      if server_name do
        # Remove existing route with same @id first (idempotent)
        delete_by_id(id)

        case post_route(server_name, id, hostname, target_port) do
          :ok ->
            routes = Map.put(state.routes, id, %{hostname: hostname, target_port: target_port})
            {:reply, :ok, %{state | routes: routes, server_name: server_name}}

          {:error, reason} ->
            Logger.error("CaddyManager: Failed to add route #{id}: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
      else
        {:reply, {:error, :no_caddy_server}, state}
      end
    else
      {:reply, {:error, :caddy_not_available}, state}
    end
  end

  @impl true
  def handle_call({:remove_route, id}, _from, state) do
    if state.caddy_available do
      delete_by_id(id)
    end

    routes = Map.delete(state.routes, id)
    {:reply, :ok, %{state | routes: routes}}
  end

  @impl true
  def handle_call(:list_routes, _from, state) do
    {:reply, state.routes, state}
  end

  @impl true
  def handle_call(:available?, _from, state) do
    {:reply, state.caddy_available, state}
  end

  # --- Private: Caddy admin API ---

  defp check_caddy_reachable do
    url = ~c"#{@caddy_admin}/config/"

    case :httpc.request(:get, {url, []}, [{:timeout, 2000}], []) do
      {:ok, {{_, code, _}, _, _}} when code in 200..299 -> true
      _ -> false
    end
  end

  # Find an existing HTTP server in Caddy's config (e.g. `srv0` from a Caddyfile).
  defp discover_server do
    url = ~c"#{@caddy_admin}/config/apps/http/servers/"

    case :httpc.request(:get, {url, []}, [{:timeout, 3000}], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        case Jason.decode(to_string(body)) do
          {:ok, servers} when is_map(servers) and map_size(servers) > 0 ->
            # Pick the first server (usually srv0 from Caddyfile)
            {name, _} = Enum.at(servers, 0)
            Logger.info("CaddyManager: Using existing Caddy server '#{name}'")
            name

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp discover_or_create_server do
    case discover_server() do
      nil ->
        # No existing server — create one for Apothecary
        create_apothecary_server()

      name ->
        name
    end
  end

  defp create_apothecary_server do
    server = %{
      "listen" => [":443", ":80"],
      "routes" => []
    }

    body = Jason.encode!(server)
    url = ~c"#{@caddy_admin}/config/apps/http/servers/apothecary"

    case caddy_put(url, body) do
      :ok ->
        Logger.info("CaddyManager: Created Caddy server 'apothecary'")
        "apothecary"

      {:error, reason} ->
        Logger.error("CaddyManager: Failed to create server: #{inspect(reason)}")
        nil
    end
  end

  defp post_route(server_name, id, hostname, target_port) do
    route = %{
      "@id" => "#{@id_prefix}#{id}",
      "match" => [%{"host" => [hostname]}],
      "handle" => [
        %{
          "handler" => "reverse_proxy",
          "upstreams" => [%{"dial" => "localhost:#{target_port}"}]
        }
      ]
    }

    body = Jason.encode!(route)
    url = ~c"#{@caddy_admin}/config/apps/http/servers/#{server_name}/routes"

    case :httpc.request(
           :post,
           {url, [], ~c"application/json", body},
           [{:timeout, 5000}],
           []
         ) do
      {:ok, {{_, code, _}, _, _}} when code in 200..299 ->
        Logger.info("CaddyManager: Added route #{id} -> #{hostname} -> localhost:#{target_port}")
        :ok

      {:ok, {{_, code, _}, _, resp_body}} ->
        {:error, "Caddy returned #{code}: #{resp_body}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_by_id(id) do
    caddy_id = "#{@id_prefix}#{id}"
    url = ~c"#{@caddy_admin}/id/#{caddy_id}"

    case :httpc.request(:delete, {url, []}, [{:timeout, 3000}], []) do
      {:ok, {{_, code, _}, _, _}} when code in 200..299 ->
        :ok

      {:ok, {{_, 404, _}, _, _}} ->
        # Not found — already removed, that's fine
        :ok

      {:ok, {{_, code, _}, _, resp_body}} ->
        Logger.warning("CaddyManager: DELETE #{caddy_id} returned #{code}: #{resp_body}")
        {:error, "Caddy returned #{code}"}

      {:error, reason} ->
        Logger.warning("CaddyManager: DELETE #{caddy_id} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp caddy_put(url, body) do
    case :httpc.request(
           :put,
           {url, [], ~c"application/json", body},
           [{:timeout, 5000}],
           []
         ) do
      {:ok, {{_, code, _}, _, _}} when code in 200..299 -> :ok
      {:ok, {{_, code, _}, _, resp_body}} -> {:error, "Caddy returned #{code}: #{resp_body}"}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Private: Mnesia sync ---

  defp sync_from_mnesia(server_name) do
    alias Apothecary.Deployment

    deployments = Apothecary.Deployments.list_by_status("running")

    routes =
      Enum.reduce(deployments, %{}, fn dep, acc ->
        slug =
          case Apothecary.Projects.get(dep.project_id) do
            {:ok, project} -> project_slug(project.name)
            _ -> dep.project_id
          end

        hostname = Deployment.resolve_hostname(dep, slug)
        route_id = "#{dep.id}-web"

        # Remove stale route first, then add fresh
        delete_by_id(route_id)

        case post_route(server_name, route_id, hostname, dep.base_port) do
          :ok -> Map.put(acc, route_id, %{hostname: hostname, target_port: dep.base_port})
          {:error, _} -> acc
        end
      end)

    if map_size(routes) > 0 do
      Logger.info("CaddyManager: Synced #{map_size(routes)} route(s) from Mnesia")
    end

    routes
  end

  # --- Public helpers ---

  @doc false
  def build_preview_hostname(branch, slug, domain) do
    safe_branch = branch |> String.replace("/", "-") |> String.replace(~r/[^a-z0-9-]/i, "")
    "#{safe_branch}--#{slug}.#{domain}"
  end

  defp project_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

end
