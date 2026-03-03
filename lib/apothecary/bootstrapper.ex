defmodule Apothecary.Bootstrapper do
  @moduledoc """
  Creates new projects from templates.

  Supports:
  - Phoenix (with or without Ecto) — uses curl installer (auto-installs phx_new)
  - React (via bun)

  Each bootstrap runs as an async task, streaming progress via PubSub.
  """

  require Logger

  alias Apothecary.{CLI, Projects}

  @pubsub Apothecary.PubSub
  @topic "bootstrap:progress"

  @type template :: :phoenix | :phoenix_no_ecto | :react

  # Phoenix project names must be valid Elixir module names
  @phoenix_name_regex ~r/^[a-z][a-z0-9_]*$/

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @doc """
  Validate a Phoenix project name.

  Phoenix names must start with a lowercase letter and contain only
  lowercase letters, digits, and underscores.
  """
  @spec validate_phoenix_name(String.t()) :: :ok | {:error, String.t()}
  def validate_phoenix_name(name) do
    cond do
      name == "" ->
        {:error, "Name cannot be empty"}

      not Regex.match?(@phoenix_name_regex, name) ->
        {:error, "Must start with a lowercase letter and contain only lowercase letters, numbers, and underscores (e.g. my_app)"}

      name in ~w(elixir test) ->
        {:error, "\"#{name}\" is a reserved name"}

      true ->
        :ok
    end
  end

  @doc """
  Bootstrap a new project asynchronously.

  Returns `{:ok, task_ref}` immediately. Progress is broadcast via PubSub.
  On completion, broadcasts `{:bootstrap_complete, result}`.
  """
  def create(parent_dir, name, template, opts \\ []) do
    path = Path.join(Path.expand(parent_dir), name)

    cond do
      File.exists?(path) ->
        {:error, :already_exists}

      template in [:phoenix, :phoenix_no_ecto] ->
        case validate_phoenix_name(name) do
          :ok ->
            start_bootstrap(parent_dir, name, path, template, opts)

          {:error, _} = err ->
            err
        end

      true ->
        start_bootstrap(parent_dir, name, path, template, opts)
    end
  end

  defp start_bootstrap(parent_dir, name, path, template, opts) do
    task =
      Task.async(fn ->
        result = do_create(parent_dir, name, path, template, opts)
        broadcast({:bootstrap_complete, name, result})
        result
      end)

    {:ok, task}
  end

  @doc "List available templates with descriptions."
  def templates do
    [
      %{
        id: :phoenix,
        name: "Phoenix",
        description: "Full-stack Elixir web app with Ecto (requires PostgreSQL)"
      },
      %{
        id: :phoenix_no_ecto,
        name: "Phoenix (no DB)",
        description: "Phoenix app without database — no PostgreSQL needed"
      },
      %{id: :react, name: "React", description: "React app via bun create"}
    ]
  end

  defp do_create(parent_dir, name, path, template, opts) do
    broadcast({:bootstrap_progress, name, "Starting #{template} project: #{name}"})

    with :ok <- ensure_parent_dir(parent_dir),
         :ok <- check_prerequisites(template),
         {:ok, _} <- run_template(parent_dir, name, path, template, opts),
         :ok <- init_git_if_needed(path),
         {:ok, project} <- register_project(path, name, template) do
      broadcast({:bootstrap_progress, name, "Project ready: #{path}"})
      {:ok, project}
    else
      {:error, reason} = err ->
        broadcast({:bootstrap_progress, name, "Failed: #{inspect(reason)}"})
        err
    end
  end

  defp ensure_parent_dir(parent_dir) do
    expanded = Path.expand(parent_dir)

    if File.dir?(expanded) do
      :ok
    else
      case File.mkdir_p(expanded) do
        :ok -> :ok
        {:error, reason} -> {:error, {:mkdir_failed, reason}}
      end
    end
  end

  # Phoenix uses the curl installer which auto-installs phx_new if needed.
  # Only requirement is that curl and mix are available.
  defp check_prerequisites(:phoenix) do
    cond do
      is_nil(System.find_executable("curl")) -> {:error, :curl_not_found}
      is_nil(System.find_executable("mix")) -> {:error, :mix_not_found}
      true -> :ok
    end
  end

  defp check_prerequisites(:phoenix_no_ecto), do: check_prerequisites(:phoenix)

  defp check_prerequisites(:react) do
    case System.find_executable("bun") do
      nil -> {:error, :bun_not_found}
      _ -> :ok
    end
  end

  # Use curl installer: automatically installs phx_new archive if not present
  defp run_template(parent_dir, name, _path, :phoenix, _opts) do
    broadcast({:bootstrap_progress, name, "Downloading and running Phoenix installer..."})

    CLI.run("sh", ["-c", "curl -fsSL https://new.phoenixframework.org/#{name} | sh"],
      cd: parent_dir,
      timeout: 180_000
    )
  end

  defp run_template(parent_dir, name, _path, :phoenix_no_ecto, _opts) do
    broadcast({:bootstrap_progress, name, "Downloading and running Phoenix installer (no database)..."})

    CLI.run("sh", ["-c", "curl -fsSL https://new.phoenixframework.org/#{name} | sh -s -- --no-ecto"],
      cd: parent_dir,
      timeout: 180_000
    )
  end

  defp run_template(parent_dir, name, _path, :react, _opts) do
    broadcast({:bootstrap_progress, name, "Running bun create react #{name}..."})

    CLI.run("bun", ["create", "react", name],
      cd: parent_dir,
      timeout: 60_000
    )
  end

  defp init_git_if_needed(path) do
    if File.dir?(Path.join(path, ".git")) do
      :ok
    else
      broadcast({:bootstrap_progress, Path.basename(path), "Initializing git repository..."})

      case CLI.run("git", ["init"], cd: path) do
        {:ok, _} ->
          # Create initial commit
          CLI.run("git", ["add", "."], cd: path)
          CLI.run("git", ["commit", "-m", "Initial commit"], cd: path)
          :ok

        {:error, reason} ->
          {:error, {:git_init_failed, reason}}
      end
    end
  end

  defp register_project(path, name, template) do
    type =
      case template do
        :phoenix -> :phoenix
        :phoenix_no_ecto -> :phoenix
        :react -> :react
      end

    Projects.create(path, name: name, type: type)
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, message)
  end
end
