defmodule Apothecary.DiffParser do
  @moduledoc "Parse unified diff output into structured file/line data."

  @doc """
  Parse raw unified diff output into a list of file maps.

  Returns:
      [%{path: "lib/foo.ex", lines: [%{type: :add | :del | :ctx | :hunk, text: "...", old_line: n, new_line: n}], adds: n, dels: n}]
  """
  def parse(raw_diff) when is_binary(raw_diff) do
    raw_diff
    |> String.split(~r/^diff --git /m)
    |> Enum.drop(1)
    |> Enum.map(&parse_file_block/1)
    |> Enum.reject(&is_nil/1)
  end

  def parse(_), do: []

  defp parse_file_block(block) do
    lines = String.split(block, "\n")
    path = extract_path(lines)

    if path do
      classified =
        lines
        |> Enum.drop_while(fn line -> not String.starts_with?(line, "@@") end)
        |> Enum.map(&classify_line/1)
        |> Enum.reject(&is_nil/1)

      {numbered, adds, dels} = add_line_numbers(classified)

      %{path: path, lines: numbered, adds: adds, dels: dels}
    end
  end

  defp add_line_numbers(lines) do
    {result, _old, _new, adds, dels} =
      Enum.reduce(lines, {[], 0, 0, 0, 0}, fn line, {acc, old_ln, new_ln, adds, dels} ->
        case line.type do
          :hunk ->
            {old_start, new_start} = parse_hunk_header(line.text)
            {[Map.merge(line, %{old_line: nil, new_line: nil}) | acc], old_start, new_start, adds, dels}

          :ctx ->
            {[Map.merge(line, %{old_line: old_ln, new_line: new_ln}) | acc], old_ln + 1, new_ln + 1, adds, dels}

          :add ->
            {[Map.merge(line, %{old_line: nil, new_line: new_ln}) | acc], old_ln, new_ln + 1, adds + 1, dels}

          :del ->
            {[Map.merge(line, %{old_line: old_ln, new_line: nil}) | acc], old_ln + 1, new_ln, adds, dels + 1}
        end
      end)

    {Enum.reverse(result), adds, dels}
  end

  defp parse_hunk_header(text) do
    case Regex.run(~r/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/, text) do
      [_, old_start, new_start] -> {String.to_integer(old_start), String.to_integer(new_start)}
      _ -> {1, 1}
    end
  end

  defp extract_path(lines) do
    Enum.find_value(lines, fn line ->
      case line do
        "+++ b/" <> path -> path
        "+++ /dev/null" -> nil
        _ -> nil
      end
    end) ||
      Enum.find_value(lines, fn line ->
        case line do
          "--- a/" <> path -> path
          _ -> nil
        end
      end)
  end

  defp classify_line("+" <> _ = line), do: %{type: :add, text: line}
  defp classify_line("-" <> _ = line), do: %{type: :del, text: line}
  defp classify_line("@@" <> _ = line), do: %{type: :hunk, text: line}
  defp classify_line("---" <> _), do: nil
  defp classify_line("+++" <> _), do: nil
  defp classify_line("index " <> _), do: nil
  defp classify_line("old mode" <> _), do: nil
  defp classify_line("new mode" <> _), do: nil
  defp classify_line("new file" <> _), do: nil
  defp classify_line("deleted file" <> _), do: nil
  defp classify_line("similarity" <> _), do: nil
  defp classify_line("rename" <> _), do: nil
  defp classify_line("Binary" <> _ = line), do: %{type: :ctx, text: line}
  defp classify_line(" " <> _ = line), do: %{type: :ctx, text: line}
  defp classify_line(""), do: nil
  defp classify_line(line), do: %{type: :ctx, text: line}
end
