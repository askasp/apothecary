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

  @doc """
  Convert a file's lines into side-by-side row pairs.

  Returns a list of rows where each row is:
    %{left: line_or_nil, right: line_or_nil, type: :ctx | :change | :hunk}

  Consecutive del/add blocks are paired together. Unmatched dels get an empty
  right side and vice versa. Context lines appear on both sides.
  """
  def to_side_by_side(lines) do
    lines
    |> chunk_by_type()
    |> Enum.flat_map(&pair_chunk/1)
  end

  defp chunk_by_type(lines) do
    # Group consecutive dels and adds together, ctx/hunk lines are standalone
    Enum.chunk_while(
      lines,
      {:init, []},
      fn line, {mode, acc} ->
        case {mode, line.type} do
          {:init, :del} -> {:cont, {:del, [line]}}
          {:init, :add} -> {:cont, {:add, [line]}}
          {:init, _} -> {:cont, {:init, []}, {:init, [line]}}
          {:del, :del} -> {:cont, {:del, [line | acc]}}
          {:del, :add} -> {:cont, {:change, {Enum.reverse(acc), [line]}}}
          {:del, _} -> {:cont, {:del, Enum.reverse(acc)}, {:init, [line]}}
          {:add, :add} -> {:cont, {:add, [line | acc]}}
          {:add, _} -> {:cont, {:add, Enum.reverse(acc)}, {:init, [line]}}
          {:change, :add} ->
            {dels, adds} = acc
            {:cont, {:change, {dels, [line | adds]}}}
          {:change, _} ->
            {dels, adds} = acc
            {:cont, {:change, {dels, Enum.reverse(adds)}}, {:init, [line]}}
        end
      end,
      fn
        {:init, []} -> {:cont, []}
        {:init, [line]} -> {:cont, {:init, [line]}, {:init, []}}
        {:del, acc} -> {:cont, {:del, Enum.reverse(acc)}, {:init, []}}
        {:add, acc} -> {:cont, {:add, Enum.reverse(acc)}, {:init, []}}
        {:change, {dels, adds}} -> {:cont, {:change, {dels, Enum.reverse(adds)}}, {:init, []}}
      end
    )
  end

  defp pair_chunk({:init, [line]}) do
    case line.type do
      :hunk -> [%{left: line, right: line, type: :hunk}]
      :ctx -> [%{left: line, right: line, type: :ctx}]
      :add -> [%{left: nil, right: line, type: :change}]
      :del -> [%{left: line, right: nil, type: :change}]
    end
  end

  defp pair_chunk({:del, dels}) do
    Enum.map(dels, fn d -> %{left: d, right: nil, type: :change} end)
  end

  defp pair_chunk({:add, adds}) do
    Enum.map(adds, fn a -> %{left: nil, right: a, type: :change} end)
  end

  defp pair_chunk({:change, {dels, adds}}) do
    max_len = max(length(dels), length(adds))
    padded_dels = dels ++ List.duplicate(nil, max_len - length(dels))
    padded_adds = adds ++ List.duplicate(nil, max_len - length(adds))

    Enum.zip(padded_dels, padded_adds)
    |> Enum.map(fn {d, a} -> %{left: d, right: a, type: :change} end)
  end

  defp pair_chunk(_), do: []
end
