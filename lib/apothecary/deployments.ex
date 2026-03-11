defmodule Apothecary.Deployments do
  @moduledoc """
  CRUD operations for deployments backed by Mnesia.

  A deployment runs a branch's preview.yml command persistently and
  routes a subdomain to its ports via Caddy reverse proxy.
  """

  require Logger

  alias Apothecary.Deployment

  @pubsub Apothecary.PubSub
  @topic "deployments:updates"

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @doc "List all deployments for a project."
  def list(project_id) do
    :mnesia.dirty_index_read(:apothecary_deployments, project_id, :project_id)
    |> Enum.map(&Deployment.from_record/1)
    |> Enum.sort_by(& &1.name)
  end

  @doc "List all deployments with a given status."
  def list_by_status(status) do
    :mnesia.dirty_index_read(:apothecary_deployments, status, :status)
    |> Enum.map(&Deployment.from_record/1)
  end

  @doc "Get a single deployment by ID."
  def get(id) do
    case :mnesia.dirty_read(:apothecary_deployments, id) do
      [record] -> {:ok, Deployment.from_record(record)}
      [] -> {:error, :not_found}
    end
  end

  @doc "Create a new deployment."
  def create(project_id, attrs) do
    id = generate_id()
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    secret_key_base = :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)
    base_port = Deployment.allocate_port(id)

    record =
      {:apothecary_deployments, id, project_id,
       Map.get(attrs, :name, Map.get(attrs, "name", "production")),
       Map.get(attrs, :branch, Map.get(attrs, "branch", "main")), "stopped", base_port,
       %{
         domain: get_attr(attrs, :domain),
         routes: Map.get(attrs, :routes, Map.get(attrs, "routes", [])),
         env_vars: Map.get(attrs, :env_vars, Map.get(attrs, "env_vars", %{})),
         secret_key_base: secret_key_base,
         error: nil,
         created_at: now,
         updated_at: now
       }}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} ->
        deployment = Deployment.from_record(record)
        broadcast({:deployment_update, deployment})
        {:ok, deployment}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Update a deployment's name, branch, or routes."
  def update(id, changes) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_deployments, id) do
          [record] ->
            updated = apply_changes(record, changes)
            :mnesia.write(updated)
            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        deployment = Deployment.from_record(record)
        broadcast({:deployment_update, deployment})
        {:ok, deployment}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Delete a deployment."
  def delete(id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_deployments, id) do
          [record] ->
            :mnesia.delete({:apothecary_deployments, id})
            record

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        deployment = Deployment.from_record(record)
        broadcast({:deployment_deleted, deployment})
        {:ok, deployment}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Set a single env var on a deployment."
  def set_env_var(id, key, value) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_deployments, id) do
          [{:apothecary_deployments, _, _, _, _, _, _, data} = record] ->
            env_vars = Map.put(data[:env_vars] || %{}, key, value)
            data = Map.put(data, :env_vars, env_vars)
            updated = put_elem(record, 7, put_timestamp(data))
            :mnesia.write(updated)
            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        deployment = Deployment.from_record(record)
        broadcast({:deployment_update, deployment})
        {:ok, deployment}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Delete a single env var from a deployment."
  def delete_env_var(id, key) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_deployments, id) do
          [{:apothecary_deployments, _, _, _, _, _, _, data} = record] ->
            env_vars = Map.delete(data[:env_vars] || %{}, key)
            data = Map.put(data, :env_vars, env_vars)
            updated = put_elem(record, 7, put_timestamp(data))
            :mnesia.write(updated)
            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        deployment = Deployment.from_record(record)
        broadcast({:deployment_update, deployment})
        {:ok, deployment}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc "Update the status (and optionally error) of a deployment."
  def update_status(id, status, opts \\ []) do
    error = Keyword.get(opts, :error)

    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(:apothecary_deployments, id) do
          [{:apothecary_deployments, dep_id, project_id, name, branch, _old_status, base_port,
            data}] ->
            data =
              data
              |> Map.put(:error, error)
              |> put_timestamp()

            updated =
              {:apothecary_deployments, dep_id, project_id, name, branch, status, base_port, data}

            :mnesia.write(updated)
            updated

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, record} ->
        deployment = Deployment.from_record(record)
        broadcast({:deployment_update, deployment})
        {:ok, deployment}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  # --- Private ---

  defp apply_changes(record, changes) do
    {table, id, project_id, name, branch, status, base_port, data} = record
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    name = get_change(changes, :name, name)
    branch = get_change(changes, :branch, branch)

    data =
      data
      |> maybe_put_change(changes, :domain)
      |> maybe_put_change(changes, :routes)
      |> Map.put(:updated_at, now)

    {table, id, project_id, name, branch, status, base_port, data}
  end

  defp get_change(changes, key, default) do
    Map.get(changes, key, Map.get(changes, to_string(key), default))
  end

  defp maybe_put_change(data, changes, key) do
    case Map.get(changes, key, Map.get(changes, to_string(key))) do
      nil -> data
      value -> Map.put(data, key, value)
    end
  end

  defp get_attr(attrs, key) do
    Map.get(attrs, key, Map.get(attrs, to_string(key)))
  end

  defp put_timestamp(data) do
    Map.put(data, :updated_at, DateTime.utc_now() |> DateTime.to_iso8601())
  end

  defp generate_id do
    hex = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "dep-#{hex}"
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, message)
  end
end
