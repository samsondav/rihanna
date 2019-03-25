defmodule Rihanna.Migration do
  @max_32_bit_signed_integer (:math.pow(2, 31) |> round) - 1

  @moduledoc """
  A set of tools for creating the Rihanna jobs table.

  Rihanna stores jobs in a table in your database. The default table name is
  "rihanna_jobs". The name is configurable by either passing it as an argument
  to the functions below or setting `:jobs_table_name` in Rihanna's config.

  #### Using Ecto

  The easiest way to create the database is with Ecto.

  Run `mix ecto.gen.migration create_rihanna_jobs` and make your migration file
  look like this:

  ```elixir
  defmodule MyApp.CreateRihannaJobs do
    use Rihanna.Migration
  end
  ```

  Now you can run `mix ecto.migrate`.

  #### Without Ecto

  Ecto is not required to run Rihanna. If you want to create the table yourself,
  without Ecto, take a look at either `statements/0` or `sql/0`.

  """

  defmacro __using__(opts) do
    table_name = Keyword.get(opts, :table_name, Rihanna.Config.jobs_table_name()) |> to_string

    quote do
      use Ecto.Migration

      def up do
        Enum.each(Rihanna.Migration.statements(unquote(table_name)), fn statement ->
          execute(statement)
        end)
      end

      def down do
        Enum.each(Rihanna.Migration.drop_statements(unquote(table_name)), fn statement ->
          execute(statement)
        end)
      end
    end
  end

  @doc """
  Returns a list of SQL statements that will drop the Rihanna jobs table if
  executed sequentially.

  By default it takes the name of the table from the application config.

  You may optionally supply a table name as an argument if you want to override
  this.

  ## Examples

      > Rihanna.Migration.drop_statements
      [...]

      > Rihanna.Migration.drop_statements("my_alternative_table_name")
      [...]
  """
  def drop_statements(table_name \\ Rihanna.Config.jobs_table_name()) do
    [
      """
      DROP TABLE IF EXISTS "#{table_name}";
      """,
      """
      DROP SEQUENCE IF EXISTS #{table_name}_id_seq;
      """
    ]
  end

  @doc """
  Returns a list of SQL statements that will create the Rihanna jobs table if
  executed sequentially.

  By default it takes the name of the table from the application config.

  You may optionally supply a table name as an argument if you want to override
  this.

  ## Examples

      > Rihanna.Migration.statements
      [...]

      > Rihanna.Migration.statements("my_alternative_table_name")
      [...]
  """
  @spec statements() :: list[String.t()]
  @spec statements(String.t() | atom) :: list[String.t()]
  def statements(table_name \\ Rihanna.Config.jobs_table_name())
      when is_binary(table_name) or is_atom(table_name) do
    [
      """
      CREATE TABLE #{table_name} (
        id int NOT NULL,
        term bytea NOT NULL,
        priority integer NOT NULL DEFAULT 19,
        enqueued_at timestamp with time zone NOT NULL,
        due_at timestamp with time zone,
        failed_at timestamp with time zone,
        fail_reason text,
        rihanna_internal_meta jsonb NOT NULL DEFAULT '{}',
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
      """,
      """
      CREATE INDEX #{table_name}_enqueued_at_id ON #{table_name} (enqueued_at ASC, id ASC);
      """
    ]
  end

  @doc """
  Returns a string of semi-colon-terminated SQL statements that you can execute
  directly to create the Rihanna jobs table.
  """
  @spec sql(String.t() | atom) :: String.t()
  def sql(table_name \\ Rihanna.Config.jobs_table_name()) do
    Enum.join(statements(table_name), "\n")
  end

  @migrate_help_message """
  The Rihanna jobs table must be created.

  Rihanna stores jobs in a table in your database.
  The default table name is "rihanna_jobs".

  The easiest way to create the database is with Ecto.

  Run `mix ecto.gen.migration create_rihanna_jobs` and make your migration look
  like this:

      defmodule MyApp.CreateRihannaJobs do
        use Rihanna.Migration
      end

  Now you can run `mix ecto.migrate`.
  """

  @doc false
  # Check that the rihanna jobs table exists
  def check_table!(pg) do
    case Postgrex.query(
           pg,
           """
           SELECT EXISTS (
             SELECT 1
             FROM information_schema.tables
             WHERE table_name = $1
           );
           """,
           [Rihanna.Job.table()]
         ) do
      {:ok, %{rows: [[true]]}} ->
        :ok

      {:ok, %{rows: [[false]]}} ->
        raise_jobs_table_missing!()
    end
  end

  @doc false
  def raise_jobs_table_missing!() do
    raise ArgumentError, @migrate_help_message
  end

  @upgrade_help_message """
  The Rihanna jobs table must be upgraded.

  The easiest way to upgrade the database is with Ecto.

  Run `mix ecto.gen.migration upgrade_rihanna_jobs` and make your migration look
  like this:

      defmodule MyApp.UpgradeRihannaJobs do
        use Rihanna.Migration.Upgrade
      end

  Now you can run `mix ecto.migrate`.
  """

  @doc false
  # Check that the required upgrades have been added
  def check_upgrade_not_required!(pg) do
    required_upgrade_columns = ["due_at", "rihanna_internal_meta"]
    table_name = Rihanna.Job.table()

    case Postgrex.query(
           pg,
           """
           SELECT column_name
           FROM information_schema.columns
           WHERE table_name = $1 and column_name = ANY($2);
           """,
           # Migration adds due_at, test if this is present
           [table_name, required_upgrade_columns]
         ) do
      {:ok, %{rows: rows}} when length(rows) < length(required_upgrade_columns) ->
        raise_upgrade_required!()

      {:ok, %{rows: rows}} when length(rows) == length(required_upgrade_columns) ->
        :ok
    end

    required_indexes = ["#{table_name}_pkey", "#{table_name}_enqueued_at_id"]

    case Postgrex.query(
           pg,
           """
           SELECT
               DISTINCT i.relname AS index_name
           FROM
               pg_class t,
               pg_class i,
               pg_index ix,
               pg_attribute a
           WHERE
               t.oid = ix.indrelid
               AND i.oid = ix.indexrelid
               AND a.attrelid = t.oid
               AND a.attnum = ANY(ix.indkey)
               AND t.relkind = 'r'
               AND t.relname = $1
               AND i.relname = ANY($2);
           """,
           [table_name, required_indexes]
         ) do
      {:ok, %{rows: rows}} when length(rows) < length(required_indexes) ->
        raise_upgrade_required!()

      {:ok, %{rows: rows}} when length(rows) == length(required_indexes) ->
        :ok
    end
  end

  @doc false
  def raise_upgrade_required!() do
    raise ArgumentError, @upgrade_help_message
  end
end
