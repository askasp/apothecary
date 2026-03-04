defmodule ApothecaryWeb.ChatLive.Context do
  @moduledoc "Pure functions for chat context state machine."

  @type t :: :wb | :oracle | {:wt, String.t()} | :recurring

  @spec initial() :: t()
  def initial, do: :wb

  @spec switch(t(), String.t() | nil) :: {:ok, t()} | {:error, String.t()}
  def switch(_current, "oracle"), do: {:ok, :oracle}
  def switch(_current, "wb"), do: {:ok, :wb}
  def switch(_current, "recurring"), do: {:ok, :recurring}

  def switch(_current, "wt:" <> id) when byte_size(id) > 0,
    do: {:ok, {:wt, id}}

  def switch(_current, id) when is_binary(id) and byte_size(id) > 0,
    do: {:ok, {:wt, id}}

  def switch(_current, _), do: {:error, "invalid context"}

  @spec label(t()) :: String.t()
  def label(:wb), do: "workbench"
  def label(:oracle), do: "oracle"
  def label(:recurring), do: "recurring"
  def label({:wt, id}), do: "wt:#{short_id(id)}"

  @spec prompt_text(t()) :: String.t()
  def prompt_text(:wb), do: "describe work to create a worktree, or /help"
  def prompt_text(:oracle), do: "ask a question..."
  def prompt_text(:recurring), do: "describe a recurring task, or /help"
  def prompt_text({:wt, _id}), do: "add a task, or /help"

  @spec prompt_hint(t()) :: String.t()
  def prompt_hint(:wb), do: "describe work to create a worktree"
  def prompt_hint(:oracle), do: "ask about the codebase"
  def prompt_hint(:recurring), do: "describe a recurring task"
  def prompt_hint({:wt, _id}), do: "type to add tasks"

  @spec push(list(), t()) :: list()
  def push(stack, ctx), do: [ctx | stack]

  @spec pop(list()) :: {t(), list()}
  def pop([]), do: {:wb, []}
  def pop([prev | rest]), do: {prev, rest}

  defp short_id(id) do
    id
    |> String.replace_leading("wt-", "")
    |> String.slice(0, 6)
  end
end
