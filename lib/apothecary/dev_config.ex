defmodule Apothecary.DevConfig do
  @moduledoc """
  Parses `.apothecary/dev.yaml` from a worktree path.

  Provides the configuration needed for DevServer to manage
  dev environment processes (setup, command, shutdown, port allocation).
  """

  @type port_spec :: %{name: String.t(), offset: non_neg_integer()}

  @type t :: %__MODULE__{
          command: String.t(),
          shutdown: String.t() | nil,
          setup: String.t() | nil,
          base_port: non_neg_integer(),
          port_count: pos_integer(),
          ports: [port_spec()],
          env: %{String.t() => String.t()}
        }

  defstruct [:command, :shutdown, :setup, :base_port, :port_count, ports: [], env: %{}]

  @config_path ".apothecary/dev.yaml"

  @doc """
  Load dev config from a worktree path.

  Returns `{:ok, config}`, `:not_found`, or `{:error, reason}`.
  """
  @spec load(String.t()) :: {:ok, t()} | :not_found | {:error, String.t()}
  def load(worktree_path) do
    path = Path.join(worktree_path, @config_path)

    if File.exists?(path) do
      case YamlElixir.read_from_file(path) do
        {:ok, yaml} -> parse(yaml)
        {:error, reason} -> {:error, "YAML parse error: #{inspect(reason)}"}
      end
    else
      :not_found
    end
  end

  defp parse(yaml) when is_map(yaml) do
    command = yaml["command"]
    port_count = yaml["port_count"]

    cond do
      is_nil(command) or command == "" ->
        {:error, "command is required in dev.yaml"}

      is_nil(port_count) or not is_integer(port_count) or port_count < 1 ->
        {:error, "port_count must be a positive integer in dev.yaml"}

      true ->
        base_port = yaml["base_port"] || 4200
        ports = parse_ports(yaml["ports"], port_count)
        env = parse_env(yaml["env"])

        case validate_ports(ports, port_count) do
          :ok ->
            {:ok,
             %__MODULE__{
               command: command,
               shutdown: yaml["shutdown"],
               setup: yaml["setup"],
               base_port: base_port,
               port_count: port_count,
               ports: ports,
               env: env
             }}

          {:error, _} = err ->
            err
        end
    end
  end

  defp parse(nil), do: {:error, "dev.yaml is empty"}
  defp parse(_), do: {:error, "dev.yaml must be a YAML map"}

  defp parse_ports(nil, port_count) do
    Enum.map(0..(port_count - 1), fn i ->
      %{name: "port_#{i}", offset: i}
    end)
  end

  defp parse_ports(ports, _port_count) when is_list(ports) do
    Enum.map(ports, fn
      %{"name" => name, "offset" => offset} when is_integer(offset) ->
        %{name: to_string(name), offset: offset}

      other ->
        %{name: inspect(other), offset: 0}
    end)
  end

  defp parse_ports(_, port_count), do: parse_ports(nil, port_count)

  defp parse_env(nil), do: %{}

  defp parse_env(env) when is_map(env) do
    Map.new(env, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp parse_env(_), do: %{}

  defp validate_ports(ports, port_count) do
    invalid = Enum.filter(ports, fn %{offset: o} -> o < 0 or o >= port_count end)

    if invalid == [] do
      :ok
    else
      names = Enum.map(invalid, & &1.name) |> Enum.join(", ")
      {:error, "port offsets out of range (0..#{port_count - 1}): #{names}"}
    end
  end

  @doc "Compute the actual port numbers given a base_port allocation."
  @spec resolve_ports(t(), non_neg_integer()) :: [%{name: String.t(), port: non_neg_integer()}]
  def resolve_ports(%__MODULE__{ports: ports}, allocated_base) do
    Enum.map(ports, fn %{name: name, offset: offset} ->
      %{name: name, port: allocated_base + offset}
    end)
  end
end
