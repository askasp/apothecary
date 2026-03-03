defmodule Mix.Tasks.Apothecary.Setup do
  @moduledoc """
  Sets up a project directory for use with Apothecary swarm agents.

  Initializes beads and starts the Dolt server.

  ## Usage

      mix apothecary.setup /path/to/project

  If no path is given, uses the current directory.
  """
  use Mix.Task

  @shortdoc "Initialize beads for a project"

  @impl true
  def run(args) do
    dir =
      case args do
        [path | _] -> Path.expand(path)
        [] -> File.cwd!()
      end

    Mix.shell().info("Setting up Apothecary for: #{dir}")

    # Check git repo
    case System.cmd("git", ["rev-parse", "--is-inside-work-tree"],
           cd: dir,
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      _ -> Mix.raise("#{dir} is not a git repository. Run `git init` first.")
    end

    # Check prerequisites
    check_prerequisite(
      "bd",
      "beads",
      "Install with: curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash"
    )

    check_prerequisite(
      "dolt",
      "dolt",
      "Install from: https://docs.dolthub.com/introduction/installation"
    )

    # Init beads
    beads_dir = Path.join(dir, ".beads")

    if File.dir?(beads_dir) do
      Mix.shell().info("  Beads already initialized")
    else
      Mix.shell().info("  Initializing beads...")

      {output, status} =
        System.cmd("bd", ["init", "--quiet"],
          cd: dir,
          stderr_to_stdout: true
        )

      if status == 0,
        do: Mix.shell().info("  #{String.trim(output)}"),
        else: Mix.raise("  Beads init failed: #{output}")
    end

    # Start Dolt server
    Mix.shell().info("  Starting Dolt server...")

    case System.cmd("bd", ["dolt", "start"], cd: dir, stderr_to_stdout: true) do
      {output, 0} -> Mix.shell().info("  #{String.trim(output)}")
      {output, _} -> Mix.shell().error("  Warning: dolt start failed: #{String.trim(output)}")
    end

    # Post-setup instructions
    Mix.shell().info("")
    Mix.shell().info("Setup complete!")
    Mix.shell().info("")
    Mix.shell().info("Files to commit to your main branch:")
    Mix.shell().info("  git add .beads/.gitignore .beads/config.yaml")
    Mix.shell().info("  git commit -m \"Add beads task tracking\"")
    Mix.shell().info("")
    Mix.shell().info("Recommended .gitignore additions:")
    Mix.shell().info("  Mnesia.*    # Apothecary database files")
    Mix.shell().info("")
    Mix.shell().info("Start Apothecary with:")
    Mix.shell().info("  APOTHECARY_PROJECT_DIR=#{dir} mix phx.server")
    Mix.shell().info("")
    Mix.shell().info("Then open http://localhost:4000")
  end

  defp check_prerequisite(binary, name, install_hint) do
    case System.find_executable(binary) do
      nil ->
        Mix.raise("#{name} (#{binary}) not found in PATH. #{install_hint}")

      path ->
        Mix.shell().info("  Found #{name}: #{path}")
    end
  end
end
