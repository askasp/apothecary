defmodule Apothecary.Store do
  @moduledoc "Mnesia initialization and table management."

  use GenServer
  require Logger

  @tables [:apothecary_concoctions, :apothecary_ingredients]

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

    create_table(:apothecary_concoctions,
      attributes: [
        :id,
        :status,
        :title,
        :priority,
        :git_path,
        :git_branch,
        :parent_concoction_id,
        :assigned_brewer_id,
        :data
      ],
      index: [:status, :parent_concoction_id, :assigned_brewer_id],
      copies_type: copies_type,
      node: node
    )

    create_table(:apothecary_ingredients,
      attributes: [:id, :concoction_id, :status, :title, :priority, :data],
      index: [:concoction_id, :status],
      copies_type: copies_type,
      node: node
    )

    :ok = :mnesia.wait_for_tables(@tables, 10_000)
    Logger.info("Mnesia tables ready: #{inspect(@tables)}")
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
        # Verify schema matches
        actual_attrs = :mnesia.table_info(name, :attributes)

        if actual_attrs != expected_attrs do
          Logger.warning(
            "Mnesia table #{name} schema mismatch!\n" <>
              "  Expected: #{inspect(expected_attrs)}\n" <>
              "  Actual:   #{inspect(actual_attrs)}\n" <>
              "  You may need to run: :mnesia.delete_table(:#{name}) and restart."
          )
        end

        :ok

      {:aborted, reason} ->
        raise "Failed to create Mnesia table #{name}: #{inspect(reason)}"
    end
  end
end
