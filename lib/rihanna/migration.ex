defmodule Rihanna.Migration do
  @max_32_bit_signed_integer (:math.pow(2, 31) |> round) - 1

  @moduledoc """
  A set of tools for creating the Rihanna jobs table.

  Rihanna stores jobs in a table in your database. The default table name is
  "rihanna_jobs". The name is configurable by either passing it as an argument
  to the functions below or setting `:jobs_table_name` in Rihanna's config.

  #### Using Ecto

  The easiest way to create the database is with Ecto. Run `mix ecto.gen.migration create_rihanna_jobs` and make your migration look like this:

  ```elixir
  defmodule MyApp.CreateRihannaJobs do
    use Rihanna.Migration
  end
  ```

  Now you can run `mix ecto.migrate`.

  #### Without Ecto

  Ecto is not required to run Rihanna. If you want to create the table yourself, without Ecto, take a look at either `statements/0` or `sql/0`.
  """

  defmacro __using__(opts) do
    table_name = Keyword.get(opts, :table_name, Rihanna.Config.jobs_table_name()) |> to_string

    quote do
      use Ecto.Migration

      def up() do
        Enum.each(Rihanna.Migration.statements(unquote(table_name)), fn statement ->
          execute(statement)
        end)
      end

      def down() do
        execute("""
        DROP TABLE(#{unquote(table_name)});
        """)
      end
    end
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
        enqueued_at timestamp with time zone NOT NULL,
        due_at timestamp with time zone,
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

  @doc """
  Returns a string of semi-colon-terminated SQL statements that you can execute
  directly to create the Rihanna jobs table.
  """
  @spec sql(String.t() | atom) :: String.t()
  def sql(table_name \\ Rihanna.Config.jobs_table_name()) do
    Enum.join(statements(table_name), "\n")
  end
end
