defmodule Apothecary.Bootstrapper do
  @moduledoc """
  Creates new projects from templates.

  Supports:
  - Phoenix (with or without Ecto)
  - React (via bun)

  Each bootstrap runs as an async task, streaming progress via PubSub.
  """

  require Logger

  alias Apothecary.{CLI, Projects}

  @pubsub Apothecary.PubSub
  @topic "bootstrap:progress"

  @type template :: :phoenix | :phoenix_no_ecto | :react

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @doc """
  Bootstrap a new project asynchronously.

  Returns `{:ok, task_ref}` immediately. Progress is broadcast via PubSub.
  On completion, broadcasts `{:bootstrap_complete, result}`.
  """
  def create(parent_dir, name, template, opts \\ []) do
    path = Path.join(Path.expand(parent_dir), name)

    if File.exists?(path) do
      {:error, :already_exists}
    else
      task =
        Task.async(fn ->
          result = do_create(parent_dir, name, path, template, opts)
          broadcast({:bootstrap_complete, name, result})
          result
        end)

      {:ok, task}
    end
  end

  @doc "List available templates with descriptions."
  def templates do
    [
      %{id: :phoenix, name: "Phoenix", description: "Full-stack Elixir web app with Ecto"},
      %{id: :phoenix_no_ecto, name: "Phoenix (no DB)", description: "Phoenix app without Ecto/database"},
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

  defp check_prerequisites(:phoenix) do
    case System.find_executable("mix") do
      nil -> {:error, :mix_not_found}
      _ -> :ok
    end
  end

  defp check_prerequisites(:phoenix_no_ecto), do: check_prerequisites(:phoenix)

  defp check_prerequisites(:react) do
    case System.find_executable("bun") do
      nil -> {:error, :bun_not_found}
      _ -> :ok
    end
  end

  defp run_template(parent_dir, name, _path, :phoenix, _opts) do
    broadcast({:bootstrap_progress, name, "Running mix phx.new #{name}..."})

    CLI.run("mix", ["phx.new", name, "--install"],
      cd: parent_dir,
      timeout: 120_000
    )
  end

  defp run_template(parent_dir, name, _path, :phoenix_no_ecto, _opts) do
    broadcast({:bootstrap_progress, name, "Running mix phx.new #{name} --no-ecto..."})

    CLI.run("mix", ["phx.new", name, "--no-ecto", "--install"],
      cd: parent_dir,
      timeout: 120_000
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
