defmodule Apothecary.Project do
  @moduledoc "Struct representing a project managed by Apothecary."

  @type project_type :: :phoenix | :react | :unknown
  @type project_status :: :active | :archived

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          path: String.t() | nil,
          status: project_status(),
          type: project_type(),
          settings: map(),
          inserted_at: String.t() | nil,
          updated_at: String.t() | nil
        }

  defstruct [
    :id,
    :name,
    :path,
    :inserted_at,
    :updated_at,
    status: :active,
    type: :unknown,
    settings: %{}
  ]

  @doc "Build a Project struct from a Mnesia record tuple."
  def from_record({:apothecary_projects, id, name, path, status, data}) do
    %__MODULE__{
      id: id,
      name: name,
      path: path,
      status: status,
      type: data[:type] || :unknown,
      settings: data[:settings] || %{},
      inserted_at: data[:inserted_at],
      updated_at: data[:updated_at]
    }
  end

  @doc "Convert to a Mnesia record tuple."
  def to_record(%__MODULE__{} = p) do
    {:apothecary_projects, p.id, p.name, p.path, p.status,
     %{
       type: p.type,
       settings: p.settings,
       inserted_at: p.inserted_at,
       updated_at: p.updated_at
     }}
  end

  @doc "Detect project type from directory contents."
  def detect_type(path) do
    cond do
      File.exists?(Path.join(path, "mix.exs")) ->
        if has_phoenix_dep?(path), do: :phoenix, else: :elixir

      File.exists?(Path.join(path, "package.json")) ->
        detect_js_type(path)

      true ->
        :unknown
    end
  end

  defp has_phoenix_dep?(path) do
    mix_path = Path.join(path, "mix.exs")

    case File.read(mix_path) do
      {:ok, content} -> String.contains?(content, ":phoenix")
      _ -> false
    end
  end

  defp detect_js_type(path) do
    pkg_path = Path.join(path, "package.json")

    case File.read(pkg_path) do
      {:ok, content} ->
        cond do
          String.contains?(content, "\"react\"") -> :react
          String.contains?(content, "\"vue\"") -> :vue
          String.contains?(content, "\"svelte\"") -> :svelte
          true -> :node
        end

      _ ->
        :node
    end
  end
end
