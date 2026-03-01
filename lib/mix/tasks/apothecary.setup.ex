defmodule Mix.Tasks.Apothecary.Setup do
  @moduledoc """
  Sets up a project directory for use with Apothecary swarm agents.

  Initializes beads and writes a CLAUDE.md with swarm instructions
  if one doesn't already exist.

  ## Usage

      mix apothecary.setup /path/to/project

  If no path is given, uses the current directory.
  """
  use Mix.Task

  @shortdoc "Initialize beads and write CLAUDE.md for a project"

  @impl true
  def run(args) do
    dir =
      case args do
        [path | _] -> Path.expand(path)
        [] -> File.cwd!()
      end

    Mix.shell().info("Setting up Apothecary for: #{dir}")

    # Check git
    case System.cmd("git", ["rev-parse", "--is-inside-work-tree"], cd: dir, stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> Mix.raise("#{dir} is not a git repository. Run `git init` first.")
    end

    # Init beads
    case System.find_executable("bd") do
      nil ->
        Mix.shell().error("bd (beads) not found. Install with: npm install -g @beads/bd")

      _bd ->
        beads_dir = Path.join(dir, ".beads")

        if File.dir?(beads_dir) do
          Mix.shell().info("  Beads already initialized")
        else
          Mix.shell().info("  Initializing beads...")
          {output, status} = System.cmd("bd", ["init", "--quiet"], cd: dir, stderr_to_stdout: true)
          if status == 0, do: Mix.shell().info("  #{String.trim(output)}"), else: Mix.shell().error("  Failed: #{output}")
        end
    end

    # Write CLAUDE.md
    claude_md_path = Path.join(dir, "CLAUDE.md")

    if File.exists?(claude_md_path) do
      Mix.shell().info("  CLAUDE.md already exists — appending beads section if missing")
      existing = File.read!(claude_md_path)

      unless String.contains?(existing, "Issue Tracking") do
        File.write!(claude_md_path, existing <> "\n\n" <> Apothecary.Startup.default_claude_md())
        Mix.shell().info("  Appended beads workflow section to CLAUDE.md")
      end
    else
      Mix.shell().info("  Writing CLAUDE.md...")
      File.write!(claude_md_path, Apothecary.Startup.default_claude_md())
      Mix.shell().info("  Created CLAUDE.md with beads workflow instructions")
    end

    Mix.shell().info("")
    Mix.shell().info("Done! Start Apothecary with:")
    Mix.shell().info("  APOTHECARY_PROJECT_DIR=#{dir} mix phx.server")
    Mix.shell().info("")
    Mix.shell().info("Then open http://localhost:4000")
  end
end
