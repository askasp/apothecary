defmodule Apothecary.DiffParser do
  @moduledoc "Parse unified diff output into structured file/line data."

  @doc """
  Parse raw unified diff output into a list of file maps.

  Returns:
      [%{path: "lib/foo.ex", lines: [%{type: :add | :del | :ctx | :hunk, text: "..."}]}]
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
      diff_lines =
        lines
        |> Enum.drop_while(fn line -> not String.starts_with?(line, "@@") end)
        |> Enum.map(&classify_line/1)
        |> Enum.reject(&is_nil/1)

      %{path: path, lines: diff_lines}
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

  @doc """
  Convert a list of flat diff lines into side-by-side rows.

  Each row is one of:
    %{type: :hunk, text: "@@..."}
    %{type: :ctx, left: %{text: t, no: n}, right: %{text: t, no: n}}
    %{type: :change, left: %{text: t, no: n} | nil, right: %{text: t, no: n} | nil}
  """
  def to_side_by_side(lines) do
    {rows, _old, _new, pending} =
      Enum.reduce(lines, {[], 0, 0, []}, fn line, {rows, old_no, new_no, dels} ->
        case line.type do
          :hunk ->
            rows = flush_dels(rows, dels)
            {old_start, new_start} = parse_hunk_numbers(line.text)
            {rows ++ [%{type: :hunk, text: line.text}], old_start, new_start, []}

          :del ->
            {rows, old_no + 1, new_no, dels ++ [%{text: line.text, no: old_no}]}

          :add ->
            case dels do
              [del | rest] ->
                row = %{
                  type: :change,
                  left: del,
                  right: %{text: line.text, no: new_no}
                }

                {rows ++ [row], old_no, new_no + 1, rest}

              [] ->
                row = %{type: :change, left: nil, right: %{text: line.text, no: new_no}}
                {rows ++ [row], old_no, new_no + 1, []}
            end

          _ ->
            rows = flush_dels(rows, dels)
            row = %{
              type: :ctx,
              left: %{text: line.text, no: old_no},
              right: %{text: line.text, no: new_no}
            }

            {rows ++ [row], old_no + 1, new_no + 1, []}
        end
      end)

    flush_dels(rows, pending)
  end

  defp flush_dels(rows, []), do: rows

  defp flush_dels(rows, dels) do
    rows ++ Enum.map(dels, fn del -> %{type: :change, left: del, right: nil} end)
  end

  defp parse_hunk_numbers(text) do
    case Regex.run(~r/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/, text) do
      [_, old_s, new_s] -> {String.to_integer(old_s), String.to_integer(new_s)}
      _ -> {1, 1}
    end
  end
end
