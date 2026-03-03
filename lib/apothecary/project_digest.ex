defmodule Apothecary.ProjectDigest do
  @moduledoc """
  Generates a compact project structure overview for brewer context.

  Accepts project_dir as a parameter. Caches per-project using persistent_term.
  """

  alias Apothecary.CLI

  @cache_ttl_ms 5 * 60 * 1_000

  @doc """
  Returns a compact project digest string suitable for inclusion in brewer prompts.
  Cached per project_dir for #{div(@cache_ttl_ms, 60_000)} minutes.
  """
  @spec generate(String.t()) :: String.t()
  def generate(project_dir) do
    case cached_digest(project_dir) do
      {:ok, digest} -> digest
      :miss -> build_and_cache(project_dir)
    end
  end

  @doc "Force regeneration of the project digest, bypassing cache."
  @spec regenerate(String.t()) :: String.t()
  def regenerate(project_dir) do
    build_and_cache(project_dir)
  end

  defp cached_digest(project_dir) do
    case :persistent_term.get({__MODULE__, :digest, project_dir}, nil) do
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

  defp build_and_cache(project_dir) do
    digest = build_digest(project_dir)

    :persistent_term.put(
      {__MODULE__, :digest, project_dir},
      {digest, System.monotonic_time(:millisecond)}
    )

    digest
  end

  defp build_digest(project_dir) do
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
        cond do
          match = Regex.run(~r/@moduledoc\s+"([^"]+)"/, content) ->
            match |> List.last() |> String.split("\n") |> hd() |> String.trim() |> truncate(80)

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
