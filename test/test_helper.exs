{:ok, _} = Application.ensure_all_started(:postgrex)
ExUnit.start()

defmodule TestHelper do
  def create_jobs_table(_ctx) do
    {:ok, pg} = Postgrex.start_link(config())

    drop_sqls = [
      """
      DROP TABLE IF EXISTS "rihanna_jobs";
      """,
      """
      DROP SEQUENCE IF EXISTS rihanna_jobs_id_seq
      """
    ]

    create_sqls = [
      """
      CREATE TABLE "rihanna_jobs" (
        id bigint NOT NULL,
        mfa bytea NOT NULL,
        enqueued_at timestamp with time zone NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        state character varying(255) DEFAULT 'ready_to_run'::character varying NOT NULL,
        heartbeat_at timestamp with time zone,
        failed_at timestamp with time zone,
        fail_reason text,
        CONSTRAINT failures_must_set_failed_at_and_fail_reason CHECK (((((state)::text = 'failed'::text) AND (failed_at IS NOT NULL) AND (fail_reason IS NOT NULL)) OR ((state)::text <> 'failed'::text))),
        CONSTRAINT only_in_progress_must_set_heartbeat_at CHECK (((heartbeat_at IS NULL) OR (((state)::text = 'in_progress'::text) AND (heartbeat_at IS NOT NULL)))),
        CONSTRAINT state_value_is_valid CHECK (((state)::text = ANY ((ARRAY['failed'::character varying, 'ready_to_run'::character varying, 'in_progress'::character varying])::text[])))
      );
      """,
      """
      CREATE SEQUENCE rihanna_jobs_id_seq
      START WITH 1
      INCREMENT BY 1
      NO MINVALUE
      NO MAXVALUE
      CACHE 1;
      """,
      """
      ALTER SEQUENCE rihanna_jobs_id_seq OWNED BY rihanna_jobs.id;
      """,
      """
      ALTER TABLE ONLY rihanna_jobs ALTER COLUMN id SET DEFAULT nextval('rihanna_jobs_id_seq'::regclass);
      """
    ]

    for statement <- drop_sqls, do: Postgrex.query!(pg, statement, [])
    for statement <- create_sqls, do: Postgrex.query!(pg, statement, [])

    {:ok, %{pg: pg}}
  end

  def truncate_postgres_jobs(ctx) do
    Postgrex.query!(
      ctx.pg,
      """
        TRUNCATE "rihanna_jobs
      """,
      []
    )

    :ok
  end

  def get_job_by_id(id, pg \\ Rihanna.Postgrex) do
    %{rows: rows} =
      Postgrex.query!(
        pg,
        """
        SELECT * FROM rihanna_jobs WHERE id = $1
        """,
        [id]
      )

    [job] = Rihanna.Job.from_sql(rows)

    job
  end

  @test_mfa {IO, :puts, ["Desperado, sittin' in an old Monte Carlo"]}

  def insert_job(_pg, :ready_to_run) do
    {:ok, job} = Rihanna.Job.enqueue(@test_mfa)
    job
  end

  def insert_job(pg, :in_progress) do
    result =
      Postgrex.query!(
        pg,
        """
        INSERT INTO "rihanna_jobs" (
          mfa,
          enqueued_at,
          updated_at,
          state,
          heartbeat_at
        )
        VALUES ($1, '2018-01-01', '2018-01-02', 'in_progress', '2018-01-02')
        RETURNING *
        """,
        [:erlang.term_to_binary(@test_mfa)]
      )

    [job] = Rihanna.Job.from_sql(result.rows)

    job
  end

  def insert_job(pg, :failed) do
    result =
      Postgrex.query!(
        pg,
        """
        INSERT INTO "rihanna_jobs" (
          mfa,
          enqueued_at,
          updated_at,
          state,
          failed_at,
          fail_reason
        )
        VALUES ($1, '2018-01-01', '2018-01-01', 'failed', '2018-01-01', 'Kaboom!')
        RETURNING *
        """,
        [:erlang.term_to_binary(@test_mfa)]
      )

    [job] = Rihanna.Job.from_sql(result.rows)

    job
  end

  defp config() do
    Keyword.put(
      Application.fetch_env!(:rihanna, :postgrex),
      :name,
      Rihanna.Postgrex
    )
  end
end
