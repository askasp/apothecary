defmodule Apothecary.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    unless Application.get_env(:apothecary, :skip_startup) do
      Apothecary.Startup.run()
    end

    children = [
      ApothecaryWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:apothecary, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Apothecary.PubSub},
      Apothecary.Store,
      Apothecary.Worktrees,
      Apothecary.BrewScheduler,
      Apothecary.PRMonitor,
      Hermes.Server.Registry,
      %{
        id: :mcp_server_supervisor,
        start:
          {Supervisor, :start_link,
           [
             [{Apothecary.MCP.Server, transport: {:streamable_http, start: true}}],
             [strategy: :one_for_one, max_restarts: 50, max_seconds: 60]
           ]},
        type: :supervisor
      },
      Apothecary.WorktreeManager,
      Apothecary.DevServer,
      {Apothecary.BrewerSupervisor, []},
      Apothecary.Dispatcher,
      ApothecaryWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Apothecary.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ApothecaryWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
