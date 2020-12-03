defmodule Rihanna.UpgradeTest do
  use ExUnit.Case, async: false
  alias Rihanna.JobDispatcher

  setup [
    :create_initial_database_schema
  ]

  setup do
    on_exit(fn ->
      drop_alternate_database_schema()
    end)
  end

  @term {IO, :puts, ["Work, work, work, work, work."]}

  describe "with an outdated database schema" do
    test "warn when `Rihanna.enqueue` used without upgrade" do
      assert_raise ArgumentError, ~r/^The Rihanna jobs table must be upgraded./, fn ->
        Rihanna.enqueue(@term)
      end
    end

    test "warn when `Rihanna.schedule` used without upgrade" do
      assert_raise ArgumentError, ~r/^The Rihanna jobs table must be upgraded./, fn ->
        Rihanna.schedule(@term, at: DateTime.utc_now())
      end
    end
  end

  describe "with an outdated database schema containing a pending job" do
    setup [
      :insert_historical_job,
      :upgrade_database_schema,
      :start_job_supervisor
    ]

    test "allows job to run after migration", %{pg: pg} do
      JobDispatcher.handle_info(:poll, %{working: %{}, pg: pg})

      assert_receive {"historical-job", _}
    end
  end

  describe "upgrade database schema using migration" do
    setup [:upgrade_database_schema]

    test "allows scheduled jobs" do
      assert {:ok, _job} = Rihanna.schedule(@term, at: DateTime.utc_now())
      assert {:ok, _job} = Rihanna.schedule(@term, in: :timer.minutes(1))
    end
  end

  describe "compatibility with multiple schemas" do
    setup [
      :upgrade_database_schema,
      :create_alternate_database_schema
    ]

    test "check_table! raises when jobs table does not exist in alternate schema", %{pg: pg} do
      assert {:ok, %{rows: [["test_schema"]]}} =
        Postgrex.query(pg, "SELECT current_schema()", [])

      assert_raise ArgumentError, ~r/The Rihanna jobs table must be created/, fn ->
        Rihanna.Migration.check_table!(pg)
      end
    end

    test "check_upgrade_not_required! checks jobs table in current schema", %{pg: pg} do
      create_structure(pg)
      upgrade_database_schema(%{pg: pg})

      assert :ok == Rihanna.Migration.check_upgrade_not_required!(pg)
    end
  end

  def insert_historical_job(%{pg: pg}) do
    term = {Rihanna.Mocks.MFAMock, :fun, [self(), "historical-job"]}

    Postgrex.query!(
      pg,
      """
        INSERT INTO "rihanna_jobs" (term, enqueued_at)
        VALUES ($1, '2018-01-01');
      """,
      [:erlang.term_to_binary(term)]
    )

    :ok
  end

  defp start_job_supervisor(_ctx) do
    {:ok, _pid} = Task.Supervisor.start_link(name: Rihanna.TaskSupervisor)
    :ok
  end

  # Create database schema from v0.6.1 to allow testing upgrade to latest
  defp create_initial_database_schema(_ctx) do
    {:ok, pg} = Postgrex.start_link(Application.fetch_env!(:rihanna, :postgrex))
    create_structure(pg)
    {:ok, %{pg: pg}}
  end

  defp create_structure(pg) do
    table_name = "rihanna_jobs"
    for statement <- drop_statements(table_name), do: Postgrex.query!(pg, statement, [])
    for statement <- initial_statements(table_name), do: Postgrex.query!(pg, statement, [])
  end

  defp create_alternate_database_schema(_ctx) do
    {:ok, pg} = Postgrex.start_link(Application.fetch_env!(:rihanna, :postgrex))
    Postgrex.query!(pg, "CREATE SCHEMA test_schema", [])
    Postgrex.query!(pg, "SET search_path TO test_schema", [])
    {:ok, %{pg: pg}}
  end

  defp drop_alternate_database_schema do
    {:ok, pg} = Postgrex.start_link(Application.fetch_env!(:rihanna, :postgrex))
    Postgrex.query!(pg, "DROP SCHEMA IF EXISTS test_schema CASCADE", [])
  end

  defp upgrade_database_schema(%{pg: pg}) do
    table_name = "rihanna_jobs"

    for statement <- Rihanna.Migration.Upgrade.statements(table_name),
        do: Postgrex.query!(pg, statement, [])

    :ok
  end

  defp drop_statements(table_name) do
    [
      """
      DROP TABLE IF EXISTS "#{table_name}";
      """,
      """
      DROP SEQUENCE IF EXISTS #{table_name}_id_seq
      """
    ]
  end

  @max_32_bit_signed_integer (:math.pow(2, 31) |> round) - 1

  defp initial_statements(table_name) do
    [
      """
      CREATE TABLE #{table_name} (
        id int NOT NULL,
        term bytea NOT NULL,
        enqueued_at timestamp with time zone NOT NULL,
        failed_at timestamp with time zone,
        fail_reason text,
        CONSTRAINT failed_at_required_fail_reason CHECK((failed_at IS NOT NULL AND fail_reason IS NOT NULL) OR (failed_at IS NULL and fail_reason IS NULL))
      );
      """,
      """
      COMMENT ON CONSTRAINT failed_at_required_fail_reason ON #{table_name} IS 'When setting failed_at you must also set a fail_reason';
      """,
      """
      CREATE SEQUENCE #{table_name}_id_seq
      START WITH 1
      INCREMENT BY 1
      MINVALUE 1
      MAXVALUE #{@max_32_bit_signed_integer}
      CACHE 1
      CYCLE;
      """,
      """
      ALTER SEQUENCE #{table_name}_id_seq OWNED BY #{table_name}.id;
      """,
      """
      ALTER TABLE ONLY #{table_name} ALTER COLUMN id SET DEFAULT nextval('#{table_name}_id_seq'::regclass);
      """,
      """
      ALTER TABLE ONLY #{table_name}
      ADD CONSTRAINT #{table_name}_pkey PRIMARY KEY (id);
      """
    ]
  end
end
