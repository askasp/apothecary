defmodule Apothecary.CLI do
  @moduledoc "Low-level shell command execution with timeout and error handling."

  require Logger

  @default_timeout 15_000
  @max_output_bytes 10 * 1_024 * 1_024

  @type result :: {:ok, String.t()} | {:error, {integer() | :timeout, String.t()}}

  @doc """
  Run an executable with the given arguments.

  Options:
    - `:cd` - working directory for the command
    - `:timeout` - max wait time in ms (default #{@default_timeout})
    - `:max_output` - max output bytes to collect (default #{@max_output_bytes})
  """
  @spec run(String.t(), [String.t()], keyword()) :: result()
  def run(command, args \\ [], opts \\ []) do
    cd = Keyword.get(opts, :cd)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_output = Keyword.get(opts, :max_output, @max_output_bytes)

    case System.find_executable(command) do
      nil ->
        {:error, {127, "executable not found: #{command}"}}

      executable ->
        port_opts = [:binary, :exit_status, :use_stdio, :stderr_to_stdout, {:args, args}]
        port_opts = if cd, do: [{:cd, to_charlist(cd)} | port_opts], else: port_opts

        port = Port.open({:spawn_executable, executable}, port_opts)
        collect_output(port, <<>>, timeout, max_output)
    end
  end

  defp collect_output(port, acc, timeout, max_output) do
    receive do
      {^port, {:data, data}} ->
        acc = acc <> data

        if byte_size(acc) > max_output do
          Logger.warning("CLI output exceeded #{div(max_output, 1024)}KB, truncating")
          collect_output(port, acc, timeout, max_output)
        else
          collect_output(port, acc, timeout, max_output)
        end

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
