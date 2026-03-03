defmodule Apothecary.Store do
  @moduledoc "Mnesia initialization and table management."

  use GenServer
  require Logger

  @tables [:apothecary_projects, :apothecary_concoctions, :apothecary_ingredients,
           :apothecary_recipes, :apothecary_settings]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    setup_mnesia()
    {:ok, %{}}
  end

  defp setup_mnesia do
    node = node()
    copies_type = Application.get_env(:apothecary, :mnesia_copies, :disc_copies)

    if copies_type == :disc_copies do
      # Disc schema required — stop mnesia (started by OTP), create schema, restart
      :mnesia.stop()

      case :mnesia.create_schema([node]) do
        :ok -> :ok
        {:error, {_, {:already_exists, _}}} -> :ok
      end

      :ok = :mnesia.start()
    end

    # For ram_copies, mnesia is already running from extra_applications

    create_table(:apothecary_projects,
      attributes: [:id, :name, :path, :status, :data],
      index: [:path, :status],
      copies_type: copies_type,
      node: node
    )

    create_table(:apothecary_concoctions,
      attributes: [
        :id,
        :project_id,
        :status,
        :title,
        :priority,
        :git_path,
        :git_branch,
        :parent_concoction_id,
        :assigned_brewer_id,
        :data
      ],
      index: [:project_id, :status, :parent_concoction_id, :assigned_brewer_id],
      copies_type: copies_type,
      node: node
    )

    create_table(:apothecary_ingredients,
      attributes: [:id, :concoction_id, :status, :title, :priority, :data],
      index: [:concoction_id, :status],
      copies_type: copies_type,
      node: node
    )

    create_table(:apothecary_recipes,
      attributes: [:id, :title, :description, :schedule, :enabled, :priority, :data],
      index: [:enabled],
      copies_type: copies_type,
      node: node
    )

    create_table(:apothecary_settings,
      attributes: [:key, :value],
      index: [],
      copies_type: copies_type,
      node: node
    )

    :ok = :mnesia.wait_for_tables(@tables, 10_000)
    Logger.info("Mnesia tables ready: #{inspect(@tables)}")

    load_persisted_settings()
  end

  @doc "Read a setting from Mnesia. Returns the value or the default."
  def get_setting(key, default \\ nil) do
    case :mnesia.transaction(fn -> :mnesia.read(:apothecary_settings, key) end) do
      {:atomic, [{:apothecary_settings, ^key, value}]} -> value
      _ -> default
    end
  end

  @doc "Write a setting to Mnesia."
  def put_setting(key, value) do
    {:atomic, :ok} =
      :mnesia.transaction(fn ->
        :mnesia.write({:apothecary_settings, key, value})
      end)

    :ok
  end

  defp load_persisted_settings do
    # Load persisted merge settings into Application env, overriding config defaults
    # but only if they were previously saved (i.e., user explicitly changed them)
    case get_setting(:auto_pr) do
      nil -> :ok
      auto -> Application.put_env(:apothecary, :auto_pr, auto)
    end
  end

  defp create_table(name, opts) do
    expected_attrs = opts[:attributes]

    table_opts =
      [
        attributes: expected_attrs,
        index: opts[:index]
      ] ++ [{opts[:copies_type], [opts[:node]]}]

    case :mnesia.create_table(name, table_opts) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, ^name}} ->
        # Verify schema matches — auto-migrate if mismatched
        actual_attrs = :mnesia.table_info(name, :attributes)

        if actual_attrs != expected_attrs do
          Logger.info("Migrating Mnesia table #{name}: #{inspect(actual_attrs)} -> #{inspect(expected_attrs)}")
          migrate_table(name, actual_attrs, expected_attrs, opts)
        end

        :ok

      {:aborted, reason} ->
        raise "Failed to create Mnesia table #{name}: #{inspect(reason)}"
    end
  end

  defp migrate_table(name, old_attrs, new_attrs, opts) do
    # Read all existing records
    old_records =
      :mnesia.transaction(fn ->
        :mnesia.foldl(fn rec, acc -> [rec | acc] end, [], name)
      end)
      |> case do
        {:atomic, records} -> records
        _ -> []
      end

    # Build a mapping from old attr positions to values
    # Record tuple: {table_name, val1, val2, ...}
    old_indexed = Enum.with_index(old_attrs, 1)
    old_map = Map.new(old_indexed, fn {attr, idx} -> {attr, idx} end)

    # Transform records to new schema
    new_records =
      Enum.map(old_records, fn old_rec ->
        values =
          Enum.map(new_attrs, fn attr ->
            case Map.get(old_map, attr) do
              nil -> nil
              idx -> elem(old_rec, idx)
            end
          end)

        List.to_tuple([name | values])
      end)

    # Delete and recreate table with new schema
    {:atomic, :ok} = :mnesia.delete_table(name)

    table_opts =
      [
        attributes: new_attrs,
        index: opts[:index]
      ] ++ [{opts[:copies_type], [opts[:node]]}]

    {:atomic, :ok} = :mnesia.create_table(name, table_opts)
    :ok = :mnesia.wait_for_tables([name], 5_000)

    # Write migrated records
    {:atomic, :ok} =
      :mnesia.transaction(fn ->
        Enum.each(new_records, &:mnesia.write/1)
      end)

    Logger.info("Migrated #{length(new_records)} records in #{name}")
  end
end
