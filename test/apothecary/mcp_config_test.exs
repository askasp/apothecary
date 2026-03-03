defmodule Apothecary.McpConfigTest do
  use ExUnit.Case, async: true

  alias Apothecary.McpConfig

  describe "build/3" do
    test "always includes the apothecary MCP server" do
      config = McpConfig.build(1, "wt-abc123", port: 4000)

      assert %{"mcpServers" => servers} = config
      assert %{"apothecary" => apothecary} = servers
      assert apothecary["type"] == "http"
      assert apothecary["url"] =~ "brewer_id=1"
      assert apothecary["url"] =~ "concoction_id=wt-abc123"
    end

    test "merges per-concoction MCP servers" do
      extra = %{
        "figma" => %{"type" => "http", "url" => "http://localhost:3845/sse"}
      }

      config = McpConfig.build(1, "wt-abc123", port: 4000, extra_mcps: extra)

      servers = config["mcpServers"]
      assert Map.has_key?(servers, "apothecary")
      assert Map.has_key?(servers, "figma")
      assert servers["figma"]["url"] == "http://localhost:3845/sse"
    end

    test "apothecary MCP cannot be overridden by extra_mcps" do
      extra = %{
        "apothecary" => %{"type" => "http", "url" => "http://evil.example.com/mcp"}
      }

      config = McpConfig.build(1, "wt-abc123", port: 4000, extra_mcps: extra)

      servers = config["mcpServers"]
      assert servers["apothecary"]["url"] =~ "localhost"
      refute servers["apothecary"]["url"] =~ "evil"
    end

    test "reads project-level .mcp.json when project_dir is set" do
      tmp_dir =
        System.tmp_dir!() |> Path.join("mcp_config_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)

      project_mcp = %{
        "mcpServers" => %{
          "github" => %{"type" => "http", "url" => "http://localhost:9999/mcp"}
        }
      }

      File.write!(Path.join(tmp_dir, ".mcp.json"), Jason.encode!(project_mcp))

      config = McpConfig.build(1, "wt-abc123", port: 4000, project_dir: tmp_dir)

      servers = config["mcpServers"]
      assert Map.has_key?(servers, "apothecary")
      assert Map.has_key?(servers, "github")
      assert servers["github"]["url"] == "http://localhost:9999/mcp"
    after
      tmp_dir = System.tmp_dir!() |> Path.join("mcp_config_test_*")
      Path.wildcard(tmp_dir) |> Enum.each(&File.rm_rf!/1)
    end

    test "per-concoction MCPs override project-level MCPs with same name" do
      tmp_dir =
        System.tmp_dir!() |> Path.join("mcp_config_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)

      project_mcp = %{
        "mcpServers" => %{
          "figma" => %{"type" => "http", "url" => "http://old-figma/mcp"}
        }
      }

      File.write!(Path.join(tmp_dir, ".mcp.json"), Jason.encode!(project_mcp))

      extra = %{
        "figma" => %{"type" => "http", "url" => "http://new-figma/mcp"}
      }

      config =
        McpConfig.build(1, "wt-abc123", port: 4000, project_dir: tmp_dir, extra_mcps: extra)

      servers = config["mcpServers"]
      assert servers["figma"]["url"] == "http://new-figma/mcp"
    after
      tmp_dir = System.tmp_dir!() |> Path.join("mcp_config_test_*")
      Path.wildcard(tmp_dir) |> Enum.each(&File.rm_rf!/1)
    end

    test "handles nil extra_mcps gracefully" do
      config = McpConfig.build(1, "wt-abc123", port: 4000, extra_mcps: nil)

      servers = config["mcpServers"]
      assert Map.has_key?(servers, "apothecary")
      assert map_size(servers) == 1
    end

    test "handles missing project .mcp.json gracefully" do
      config = McpConfig.build(1, "wt-abc123", port: 4000, project_dir: "/nonexistent/path")

      servers = config["mcpServers"]
      assert Map.has_key?(servers, "apothecary")
      assert map_size(servers) == 1
    end

    test "handles malformed project .mcp.json gracefully" do
      tmp_dir =
        System.tmp_dir!() |> Path.join("mcp_config_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      File.write!(Path.join(tmp_dir, ".mcp.json"), "not json at all")

      config = McpConfig.build(1, "wt-abc123", port: 4000, project_dir: tmp_dir)

      servers = config["mcpServers"]
      assert Map.has_key?(servers, "apothecary")
      assert map_size(servers) == 1
    after
      tmp_dir = System.tmp_dir!() |> Path.join("mcp_config_test_*")
      Path.wildcard(tmp_dir) |> Enum.each(&File.rm_rf!/1)
    end
  end

  describe "read_project_mcp_servers/1" do
    test "returns empty map for nil project_dir" do
      assert McpConfig.read_project_mcp_servers(nil) == %{}
    end

    test "returns empty map when file doesn't exist" do
      assert McpConfig.read_project_mcp_servers("/nonexistent") == %{}
    end
  end
end
