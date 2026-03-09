defmodule Apothecary.FileTree do
  @moduledoc "Scans a project directory for tracked files using git ls-files."

  alias Apothecary.CLI

  @doc """
  Returns a list of relative file paths tracked by git in the given project directory.
  Respects .gitignore automatically since git ls-files only returns tracked files.
  """
  @spec list_files(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_files(project_dir) do
    case CLI.run("git", ["ls-files"], cd: project_dir) do
      {:ok, output} ->
        files =
          output
          |> String.split("\n", trim: true)
          |> Enum.sort()

        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search files matching a query string. Case-insensitive fuzzy match on path segments.
  Returns at most `limit` results.
  """
  @spec search(String.t(), [String.t()], pos_integer()) :: [String.t()]
  def search(query, files, limit \\ 15) do
    query = String.downcase(query)

    files
    |> Enum.filter(fn path ->
      String.contains?(String.downcase(path), query)
    end)
    |> Enum.sort_by(fn path ->
      downcased = String.downcase(path)
      basename = Path.basename(downcased)

      cond do
        basename == query -> {0, String.length(path)}
        String.starts_with?(basename, query) -> {1, String.length(path)}
        String.contains?(basename, query) -> {2, String.length(path)}
        true -> {3, String.length(path)}
      end
    end)
    |> Enum.take(limit)
  end
end
