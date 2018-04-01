defmodule Rihanna.Migration do
  @default_table_name Rihanna.Config.jobs_table_name()
  @max_32_bit_signed_integer (:math.pow(2, 31) |> round) - 1

  #  TODO: __using__ for ecto

  defmacro up(table_name \\ @default_table_name) do
    quote do
      Enum.each(statements(unquote(table_name)), fn ->
        execute(statement)
      end)
    end
  end

  defmacro down(table_name \\ @default_table_name) do
    quote do
      execute("""
      DROP TABLE(#{unquote(table_name)});
      """)
    end
  end

  def statements(table_name \\ @default_table_name) do
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

  def sql(table_name \\ @default_table_name) do
    Enum.join(statements(table_name), "\n")
  end
end
