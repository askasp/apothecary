defmodule Apothecary.Deployment do
  @moduledoc """
  Struct representing a deployment — a persistently-running branch
  served via Caddy reverse proxy.

  Mnesia record: `{:apothecary_deployments, id, project_id, name, branch, status, base_port, data}`
  where `data` holds routes, env_vars, secret_key_base, error, and timestamps.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          project_id: String.t(),
          name: String.t(),
          branch: String.t(),
          status: String.t(),
          base_port: non_neg_integer(),
          domain: String.t() | nil,
          routes: [map()],
          env_vars: map(),
          secret_key_base: String.t(),
          error: String.t() | nil,
          created_at: String.t() | nil,
          updated_at: String.t() | nil
        }

  defstruct [
    :id,
    :project_id,
    :name,
    :branch,
    :base_port,
    :domain,
    :secret_key_base,
    :error,
    :created_at,
    :updated_at,
    status: "stopped",
    routes: [],
    env_vars: %{}
  ]

  @doc "Build a Deployment struct from a Mnesia record tuple."
  def from_record({:apothecary_deployments, id, project_id, name, branch, status, base_port, data}) do
    %__MODULE__{
      id: id,
      project_id: project_id,
      name: name,
      branch: branch,
      status: status,
      base_port: base_port,
      domain: data[:domain],
      routes: data[:routes] || [],
      env_vars: data[:env_vars] || %{},
      secret_key_base: data[:secret_key_base],
      error: data[:error],
      created_at: data[:created_at],
      updated_at: data[:updated_at]
    }
  end

  @doc "Convert to a Mnesia record tuple."
  def to_record(%__MODULE__{} = d) do
    {:apothecary_deployments, d.id, d.project_id, d.name, d.branch, d.status, d.base_port,
     %{
       domain: d.domain,
       routes: d.routes,
       env_vars: d.env_vars,
       secret_key_base: d.secret_key_base,
       error: d.error,
       created_at: d.created_at,
       updated_at: d.updated_at
     }}
  end

  @doc "Allocate a deterministic base port from the deployment ID (range 20000-24999)."
  def allocate_port(deployment_id) do
    20_000 + :erlang.phash2(deployment_id, 5000)
  end

  @doc """
  Resolve the public hostname for a deployment.

  If `domain` is set on the deployment, uses that directly.
  Otherwise derives from the distillery name + project slug + PLATFORM_DOMAIN:
  - name "production" → `{project_slug}.{platform_domain}`
  - any other name    → `{name}--{project_slug}.{platform_domain}`
  """
  def resolve_hostname(%__MODULE__{domain: domain}, _project_slug)
      when is_binary(domain) and domain != "" do
    domain
  end

  def resolve_hostname(%__MODULE__{name: name}, project_slug) do
    platform_domain = Apothecary.platform_domain() || "localhost"

    if name == "production" do
      "#{project_slug}.#{platform_domain}"
    else
      safe_name =
        name
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9-]/, "-")
        |> String.trim("-")

      "#{safe_name}--#{project_slug}.#{platform_domain}"
    end
  end
end
