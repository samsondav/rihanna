defmodule Rihanna.Migration.Upgrade do
  @moduledoc """
  A set of tools for upgrading an existing Rihanna jobs table.

  Rihanna stores jobs in a table in your database. The default table name is
  "rihanna_jobs". The name is configurable by either passing it as an argument
  to the functions below or setting `:jobs_table_name` in Rihanna's config.

  #### Using Ecto

  The easiest way to upgrade the database is with Ecto.

  Run `mix ecto.gen.migration upgrade_rihanna_jobs` and make your migration look
  like this:

  ```elixir
  defmodule MyApp.UpgradeRihannaJobs do
    use Rihanna.Migration.Upgrade
  end
  ```

  Now you can run `mix ecto.migrate`.

  #### Without Ecto

  Ecto is not required to run Rihanna. If you want to upgrade the table yourself,
  without Ecto, take a look at either `statements/0` or `sql/0`.

  """

  alias Rihanna.Migration.Upgrade

  defmacro __using__(opts) do
    table_name = Keyword.get(opts, :table_name, Rihanna.Config.jobs_table_name()) |> to_string

    quote do
      use Ecto.Migration

      def up do
        Enum.each(Upgrade.statements(unquote(table_name)), &execute/1)
      end

      def down do
        Enum.each(Upgrade.drop_statements(unquote(table_name)), &execute/1)
      end
    end
  end

  @doc """
  Returns a list of SQL statements that will rollback the upgrade of Rihanna jobs table if
  executed sequentially.

  By default it takes the name of the table from the application config.

  You may optionally supply a table name as an argument if you want to override
  this.

  ## Examples

      > Rihanna.Migration.Upgrade.drop_statements
      [...]

      > Rihanna.Migration.Upgrade.drop_statements("my_alternative_table_name")
      [...]
  """
  @spec drop_statements() :: list[String.t()]
  @spec drop_statements(String.t() | atom) :: list[String.t()]
  def drop_statements(table_name \\ Rihanna.Config.jobs_table_name()) do
    [
      """
      ALTER TABLE #{table_name} DROP COLUMN due_at;
      """,
      """
      ALTER TABLE #{table_name} DROP COLUMN rihanna_internal_meta;
      """,
      """
      ALTER TABLE #{table_name} DROP COLUMN priority;
      """,
      """
      DO $$
          BEGIN
              DROP INDEX IF EXISTS rihanna_jobs_priority_enqueued_at_id;
              CREATE INDEX IF NOT EXISTS rihanna_jobs_enqueued_at_id ON rihanna_jobs (enqueued_at ASC, id ASC);
          END;
      $$
      """
    ]
  end

  @doc """
  Returns a list of SQL statements that will upgrade the Rihanna jobs table if
  executed sequentially.

  By default it takes the name of the table from the application config.

  You may optionally supply a table name as an argument if you want to override
  this.

  ## Examples

      > Rihanna.Migration.Upgrade.statements
      [...]

      > Rihanna.Migration.Upgrade.statements("my_alternative_table_name")
      [...]
  """
  @spec statements() :: list[String.t()]
  @spec statements(String.t() | atom) :: list[String.t()]
  def statements(table_name \\ Rihanna.Config.jobs_table_name())
      when is_binary(table_name) or is_atom(table_name) do
    [
      # Postgres versions earlier than v9.6 do not suppport `IF EXISTS` predicates
      # on alter table commands. For backwards compatibility we're using a try/catch
      # approach to add the `due_at` column idempotently.
      """
      DO $$
          BEGIN
              BEGIN
                  ALTER TABLE #{table_name} ADD COLUMN due_at timestamp with time zone;
                  ALTER TABLE #{table_name} ADD COLUMN rihanna_internal_meta jsonb NOT NULL DEFAULT '{}';
              EXCEPTION
                  WHEN duplicate_column THEN
                  RAISE NOTICE 'column already exists in #{table_name}.';
              END;
          END;
      $$
      """,
      """
      CREATE INDEX IF NOT EXISTS rihanna_jobs_enqueued_at_id ON rihanna_jobs (enqueued_at ASC, id ASC);
      """,
      """
      ALTER TABLE #{table_name} ADD COLUMN priority integer NOT NULL DEFAULT 19;
      """,
      """
      DO $$
          BEGIN
              DROP INDEX IF EXISTS rihanna_jobs_enqueued_at_id;
              CREATE INDEX IF NOT EXISTS rihanna_jobs_priority_enqueued_at_id ON rihanna_jobs (priority ASC, enqueued_at ASC, id ASC);
          END;
      $$
      """
    ]
  end

  @doc """
  Returns a string of semi-colon-terminated SQL statements that you can execute
  directly to upgrade the Rihanna jobs table.
  """
  @spec sql(String.t() | atom) :: String.t()
  def sql(table_name \\ Rihanna.Config.jobs_table_name()) do
    Enum.join(statements(table_name), "\n")
  end
end
