defmodule Apothecary.DevConfig do
  @moduledoc """
  Parses `.apothecary/preview.yml` from a worktree path.

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

  @config_path ".apothecary/preview.yml"

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
        {:error, "command is required in preview.yml"}

      is_nil(port_count) or not is_integer(port_count) or port_count < 1 ->
        {:error, "port_count must be a positive integer in preview.yml"}

      true ->
        base_port = yaml["base_port"] || guess_base_port(command)
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

  defp parse(nil), do: {:error, "preview.yml is empty"}
  defp parse(_), do: {:error, "preview.yml must be a YAML map"}

  # Infer a reasonable base_port from the command when not explicitly set.
  defp guess_base_port(command) when is_binary(command) do
    cmd = String.downcase(command)

    cond do
      String.contains?(cmd, "phx.server") -> 4000
      String.contains?(cmd, "mix") -> 4000
      String.contains?(cmd, "dev") -> 5173
      String.contains?(cmd, "start") -> 3000
      true -> 3000
    end
  end

  defp guess_base_port(_), do: 3000

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

  @doc """
  Auto-detect a dev config for a project directory based on common patterns.

  Returns `{:ok, config}` or `:not_detected`.
  """
  @spec detect(String.t()) :: {:ok, t()} | :not_detected
  def detect(project_dir) do
    cond do
      File.exists?(Path.join(project_dir, "mix.exs")) ->
        detect_elixir(project_dir)

      File.exists?(Path.join(project_dir, "package.json")) ->
        detect_node(project_dir)

      true ->
        :not_detected
    end
  end

  defp detect_elixir(project_dir) do
    mix_content = File.read!(Path.join(project_dir, "mix.exs"))

    if String.contains?(mix_content, ":phoenix") do
      {:ok,
       %__MODULE__{
         command: "mix phx.server",
         setup: "mix deps.get",
         base_port: 4000,
         port_count: 1,
         ports: [%{name: "web", offset: 0}],
         env: %{"MIX_ENV" => "dev"}
       }}
    else
      :not_detected
    end
  end

  defp detect_node(project_dir) do
    case File.read(Path.join(project_dir, "package.json")) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, pkg} ->
            scripts = Map.get(pkg, "scripts", %{})

            cond do
              Map.has_key?(scripts, "dev") ->
                runner =
                  if File.exists?(Path.join(project_dir, "bun.lockb")), do: "bun", else: "npm"

                {:ok,
                 %__MODULE__{
                   command: "#{runner} run dev",
                   setup: "#{runner} install",
                   base_port: 5173,
                   port_count: 1,
                   ports: [%{name: "web", offset: 0}],
                   env: %{}
                 }}

              Map.has_key?(scripts, "start") ->
                runner =
                  if File.exists?(Path.join(project_dir, "bun.lockb")), do: "bun", else: "npm"

                {:ok,
                 %__MODULE__{
                   command: "#{runner} start",
                   setup: "#{runner} install",
                   base_port: 3000,
                   port_count: 1,
                   ports: [%{name: "web", offset: 0}],
                   env: %{}
                 }}

              true ->
                :not_detected
            end

          {:error, _} ->
            :not_detected
        end

      {:error, _} ->
        :not_detected
    end
  end
end
