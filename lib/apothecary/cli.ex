defmodule Apothecary.CLI do
  @moduledoc "Low-level shell command execution with timeout and error handling."

  require Logger

  @default_timeout 15_000

  @type result :: {:ok, String.t()} | {:error, {integer() | :timeout, String.t()}}

  @doc """
  Run an executable with the given arguments.

  Options:
    - `:cd` - working directory for the command
    - `:timeout` - max wait time in ms (default #{@default_timeout})
  """
  @spec run(String.t(), [String.t()], keyword()) :: result()
  def run(command, args \\ [], opts \\ []) do
    cd = Keyword.get(opts, :cd)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case System.find_executable(command) do
      nil ->
        {:error, {127, "executable not found: #{command}"}}

      executable ->
        port_opts = [:binary, :exit_status, :use_stdio, :stderr_to_stdout, {:args, args}]
        port_opts = if cd, do: [{:cd, to_charlist(cd)} | port_opts], else: port_opts

        port = Port.open({:spawn_executable, executable}, port_opts)
        collect_output(port, <<>>, timeout)
    end
  end

  defp collect_output(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        collect_output(port, acc <> data, timeout)

      {^port, {:exit_status, 0}} ->
        {:ok, String.trim(acc)}

      {^port, {:exit_status, code}} ->
        {:error, {code, String.trim(acc)}}
    after
      timeout ->
        Port.close(port)
        {:error, {:timeout, String.trim(acc)}}
    end
  end
end
