defmodule Apothecary.FileTree do
  @moduledoc "Scans the project directory for tracked files using git ls-files."

  alias Apothecary.CLI

  @doc """
  Returns a list of relative file paths tracked by git in the project directory.
  Respects .gitignore automatically since git ls-files only returns tracked files.
  """
  @spec list_files() :: {:ok, [String.t()]} | {:error, term()}
  def list_files do
    project_dir = Application.get_env(:apothecary, :project_dir, File.cwd!())

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
        # Exact basename match gets highest priority
        basename == query -> {0, String.length(path)}
        # Basename starts with query
        String.starts_with?(basename, query) -> {1, String.length(path)}
        # Basename contains query
        String.contains?(basename, query) -> {2, String.length(path)}
        # Path contains query
        true -> {3, String.length(path)}
      end
    end)
    |> Enum.take(limit)
  end
end
