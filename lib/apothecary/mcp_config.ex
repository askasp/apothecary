defmodule Apothecary.McpConfig do
  @moduledoc """
  Builds the .mcp.json config for brewer worktrees by merging:
  1. Project-level MCP servers (from the main project's .mcp.json)
  2. Per-worktree MCP servers (from the worktree's mcp_servers field)
  3. The apothecary orchestrator MCP server (always included, cannot be overridden)
  """

  @doc """
  Build the complete MCP config map for a worktree.

  Returns a map ready to be JSON-encoded and written to .mcp.json.
  """
  def build(agent_id, worktree_id, opts \\ []) do
    port = Keyword.get(opts, :port, Application.get_env(:apothecary, :port, 4000))
    project_dir = Keyword.get(opts, :project_dir, Application.get_env(:apothecary, :project_dir))
    extra_mcps = Keyword.get(opts, :extra_mcps, %{})

    apothecary_mcp = %{
      "apothecary" => %{
        "type" => "http",
        "url" =>
          "http://localhost:#{port}/mcp?brewer_id=#{agent_id}&worktree_id=#{worktree_id}"
      }
    }

    project_mcps = read_project_mcp_servers(project_dir)

    # Merge order: project-level < per-worktree < apothecary (apothecary always wins)
    servers =
      project_mcps
      |> Map.merge(normalize(extra_mcps))
      |> Map.merge(apothecary_mcp)

    %{"mcpServers" => servers}
  end

  @doc """
  Read MCP servers from a project's .mcp.json file.

  Returns a map of server name => config, or an empty map if not found.
  """
  def read_project_mcp_servers(nil), do: %{}

  def read_project_mcp_servers(project_dir) do
    mcp_path = Path.join(project_dir, ".mcp.json")

    case File.read(mcp_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"mcpServers" => servers}} when is_map(servers) -> servers
          _ -> %{}
        end

      {:error, _} ->
        %{}
    end
  end

  @doc "Normalize MCP servers input to a map."
  def normalize(servers) when is_map(servers), do: servers
  def normalize(_), do: %{}
end
