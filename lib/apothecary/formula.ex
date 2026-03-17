defmodule Apothecary.Formula do
  @moduledoc """
  A formula is a named template of tasks that can be injected into a worktree.

  Each task in the formula has a title, optional description, and an optional
  agent_md reference that tells the brewer how to behave for that task.

  Formulas are stored in project settings under the :formulas key as a map
  of name => %{description: ..., tasks: [...]}.
  """

  @doc """
  List built-in agent configs available in priv/agents/.
  Returns a list of {name, path} tuples.
  """
  def builtin_agents do
    agents_dir = Application.app_dir(:apothecary, "priv/agents")

    case File.ls(agents_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(fn file ->
          name = String.replace_trailing(file, ".md", "")
          {name, Path.join(agents_dir, file)}
        end)
        |> Enum.sort_by(&elem(&1, 0))

      _ ->
        []
    end
  end

  @doc """
  Get the content of an agent config by name.
  Looks in built-in agents first, then in the project repo.
  """
  def agent_content(name, project_dir \\ nil) do
    # Try built-in first
    builtin_path = Application.app_dir(:apothecary, "priv/agents/#{name}.md")

    case File.read(builtin_path) do
      {:ok, content} ->
        {:ok, content}

      _ ->
        # Try project repo
        if project_dir do
          project_path = Path.join(project_dir, ".apothecary/agents/#{name}.md")

          case File.read(project_path) do
            {:ok, content} -> {:ok, content}
            _ -> {:error, :not_found}
          end
        else
          {:error, :not_found}
        end
    end
  end

  @doc "List agent names available (built-in + project-local)."
  def available_agents(project_dir \\ nil) do
    builtin =
      builtin_agents()
      |> Enum.map(fn {name, _path} -> %{name: name, source: :builtin} end)

    project =
      if project_dir do
        agents_dir = Path.join(project_dir, ".apothecary/agents")

        case File.ls(agents_dir) do
          {:ok, files} ->
            files
            |> Enum.filter(&String.ends_with?(&1, ".md"))
            |> Enum.map(fn file ->
              %{name: String.replace_trailing(file, ".md", ""), source: :project}
            end)

          _ ->
            []
        end
      else
        []
      end

    (builtin ++ project)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  @doc "Default formula definitions seeded on new projects."
  def defaults do
    %{
      "quality-gate" => %{
        "description" => "standard QA — test, lint, review",
        "tasks" => [
          %{"title" => "mix compile --warnings-as-errors", "agent_md" => nil},
          %{"title" => "mix format --check-formatted", "agent_md" => nil},
          %{"title" => "mix test", "agent_md" => nil},
          %{"title" => "Review diff with main", "agent_md" => "reviewer"},
          %{"title" => "Create pull request", "agent_md" => nil}
        ]
      },
      "review" => %{
        "description" => "code review and fix cycle",
        "tasks" => [
          %{"title" => "Review diff with main", "agent_md" => "reviewer"},
          %{"title" => "Fix review findings", "agent_md" => "reviewer_fix"}
        ]
      }
    }
  end
end
