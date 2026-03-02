defmodule Apothecary.ProjectDigest do
  @moduledoc """
  Generates a compact project structure overview for brewer context.

  Instead of forcing every new brewer to explore the entire codebase,
  this module generates a digest containing:
  - A grouped file tree of key directories (lib/, test/)
  - One-line @moduledoc extractions for each Elixir module
  - Key config files listed

  The digest is cached and only regenerated when the file list changes
  (based on git ls-files hash).
  """

  alias Apothecary.CLI

  @cache_ttl_ms 5 * 60 * 1_000

  @doc """
  Returns a compact project digest string suitable for inclusion in brewer prompts.
  Cached for #{div(@cache_ttl_ms, 60_000)} minutes.
  """
  @spec generate() :: String.t()
  def generate do
    case cached_digest() do
      {:ok, digest} -> digest
      :miss -> build_and_cache()
    end
  end

  @doc """
  Force regeneration of the project digest, bypassing cache.
  """
  @spec regenerate() :: String.t()
  def regenerate do
    build_and_cache()
  end

  # Cache using persistent_term (fast reads, no GenServer needed)

  defp cached_digest do
    case :persistent_term.get({__MODULE__, :digest}, nil) do
      {digest, timestamp} ->
        if System.monotonic_time(:millisecond) - timestamp < @cache_ttl_ms do
          {:ok, digest}
        else
          :miss
        end

      nil ->
        :miss
    end
  end

  defp build_and_cache do
    digest = build_digest()
    :persistent_term.put({__MODULE__, :digest}, {digest, System.monotonic_time(:millisecond)})
    digest
  end

  defp build_digest do
    project_dir = Application.get_env(:apothecary, :project_dir, File.cwd!())

    files =
      case CLI.run("git", ["ls-files"], cd: project_dir) do
        {:ok, output} -> String.split(output, "\n", trim: true)
        {:error, _} -> []
      end

    if files == [] do
      "(could not read project files)"
    else
      parts =
        [
          build_module_map(files, project_dir),
          build_config_section(files),
          build_test_section(files)
        ]
        |> Enum.reject(&(&1 == ""))

      Enum.join(parts, "\n\n")
    end
  end

  defp build_module_map(files, project_dir) do
    elixir_files =
      files
      |> Enum.filter(&String.ends_with?(&1, ".ex"))
      |> Enum.filter(&String.starts_with?(&1, "lib/"))
      |> Enum.reject(&String.starts_with?(&1, "lib/mix/"))
      |> Enum.sort()

    if elixir_files == [] do
      ""
    else
      lines =
        elixir_files
        |> Enum.map(fn file ->
          doc = extract_moduledoc(Path.join(project_dir, file))
          if doc, do: "  #{file} — #{doc}", else: "  #{file}"
        end)

      "### Source Modules\n" <> Enum.join(lines, "\n")
    end
  end

  defp build_config_section(files) do
    config_files =
      files
      |> Enum.filter(fn f ->
        String.starts_with?(f, "config/") or
          f in ["mix.exs", "CLAUDE.md", "AGENTS.md", ".formatter.exs"]
      end)
      |> Enum.sort()

    if config_files == [] do
      ""
    else
      lines = Enum.map(config_files, &"  #{&1}")
      "### Config & Project Files\n" <> Enum.join(lines, "\n")
    end
  end

  defp build_test_section(files) do
    test_files =
      files
      |> Enum.filter(&String.starts_with?(&1, "test/"))
      |> Enum.filter(&String.ends_with?(&1, "_test.exs"))
      |> Enum.sort()

    if test_files == [] do
      ""
    else
      lines = Enum.map(test_files, &"  #{&1}")
      "### Test Files\n" <> Enum.join(lines, "\n")
    end
  end

  @doc false
  def extract_moduledoc(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        # Extract @moduledoc string — supports both single-line and heredoc
        cond do
          # Single-line: @moduledoc "Some description"
          match = Regex.run(~r/@moduledoc\s+"([^"]+)"/, content) ->
            match |> List.last() |> String.split("\n") |> hd() |> String.trim() |> truncate(80)

          # Heredoc: @moduledoc """ ... """
          match = Regex.run(~r/@moduledoc\s+"""\n\s*(.+?)(?:\n|""")/, content) ->
            match |> List.last() |> String.trim() |> truncate(80)

          true ->
            nil
        end

      {:error, _} ->
        nil
    end
  end

  defp truncate(string, max) do
    if String.length(string) > max do
      String.slice(string, 0, max - 3) <> "..."
    else
      string
    end
  end
end
