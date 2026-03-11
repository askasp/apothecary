defmodule Apothecary.PortProcess do
  @moduledoc """
  Shared helpers for spawning and managing OS processes via Erlang Ports.

  Used by both DevServer and DeploymentServer to avoid duplication of
  the spawn_command, run_setup, health check, and error diagnosis logic.
  """

  require Logger

  @doc """
  Spawn a command as an Erlang Port.

  Returns `{:ok, port}` or `{:error, reason}`.
  Env should be a list of `{key, value}` string tuples.
  """
  def spawn_command(command, working_dir, env) do
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
          {:cd, to_charlist(working_dir)}
        ])

      {:ok, port}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Run a setup command synchronously.

  Returns `:ok` or `{:error, reason}`.
  """
  def run_setup(nil, _path, _env), do: :ok
  def run_setup("", _path, _env), do: :ok

  def run_setup(setup_cmd, working_dir, env) do
    Logger.info("PortProcess running setup: #{setup_cmd} in #{working_dir}")

    try do
      case System.cmd("sh", ["-c", setup_cmd],
             cd: working_dir,
             env: env,
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          Logger.info("PortProcess setup completed: #{String.slice(output, 0, 200)}")
          :ok

        {output, code} ->
          {:error, "exit code #{code}: #{String.slice(output, 0, 500)}"}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc "Check if a TCP port is accepting connections on localhost."
  def tcp_port_open?(port) do
    case :gen_tcp.connect(~c"localhost", port, [], 500) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  @doc "Diagnose an error from process exit code and output."
  def diagnose_error(code, output, base_port) do
    output_text = Enum.join(output, "\n")

    cond do
      port_conflict?(output_text) ->
        "Port conflict (port #{base_port} already in use). Exit code #{code}"

      String.contains?(output_text, "ENOENT") ->
        "Command not found. Exit code #{code}"

      String.contains?(output_text, "permission denied") ->
        "Permission denied. Exit code #{code}"

      true ->
        "Process exited with code #{code}"
    end
  end

  defp port_conflict?(output) do
    String.contains?(output, "EADDRINUSE") or
      String.contains?(output, "address already in use") or
      String.contains?(output, "port is already allocated") or
      String.contains?(output, "Address already in use") or
      String.contains?(output, "bind EADDRINUSE")
  end
end
