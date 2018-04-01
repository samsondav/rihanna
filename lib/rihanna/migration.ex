defmodule Rihanna.Migration do
  @max_32_bit_signed_integer (:math.pow(2, 31) |> round) - 1

  @moduledoc """
  TODO: Write something here...
  """

  @doc """
  TODO: using with Ecto...
  """
  defmacro __using__(opts) do
    table_name = Keyword.get(opts, :table_name, Rihanna.Config.jobs_table_name()) |> to_string

    quote do
      def up() do
        Enum.each(statements(unquote(table_name)), fn ->
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

    iex> Rihanna.Migration.statements
    [...]

    iex> Rihanna.Migration.statements("my_alternative_table_name")
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
        mfa bytea NOT NULL,
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

  def sql(table_name \\ Rihanna.Config.jobs_table_name()) do
    Enum.join(statements(table_name), "\n")
  end
end
