defmodule TestHelper do
  defmacro assert_unordered_list_equality(list_1, list_2) do
    quote do
      assert Enum.sort(unquote(list_1)) == Enum.sort(unquote(list_2))
    end
  end

  def create_jobs_table(_ctx) do
    {:ok, pg} = Postgrex.start_link(Application.fetch_env!(:rihanna, :postgrex))

    drop_jobs_table(%{pg: pg})

    create_sqls = Rihanna.Migration.statements()

    for statement <- create_sqls, do: Postgrex.query!(pg, statement, [])

    {:ok, %{pg: pg}}
  end

  def drop_jobs_table(%{pg: pg}) do
    drop_sqls = [
      """
      DROP TABLE IF EXISTS "rihanna_jobs";
      """,
      """
      DROP SEQUENCE IF EXISTS rihanna_jobs_id_seq
      """
    ]

    for statement <- drop_sqls, do: Postgrex.query!(pg, statement, [])

    {:ok, %{pg: pg}}
  end

  def drop_jobs_table(_ctx) do
    {:ok, pg} = Postgrex.start_link(Application.fetch_env!(:rihanna, :postgrex))

    drop_jobs_table(%{pg: pg})
  end

  def truncate_postgres_jobs(ctx) do
    Postgrex.query!(
      ctx.pg,
      """
      TRUNCATE "rihanna_jobs"
      """,
      []
    )

    :ok
  end

  def get_job_by_id(conn, id) when is_integer(id) do
    exec =
      case conn do
        TestApp.Repo -> &Ecto.Adapters.SQL.query!/3
        _ when is_pid(conn) -> &Postgrex.query!/3
      end

    %{rows: rows} =
      exec.(
        conn,
        """
        SELECT id, term, enqueued_at, due_at, failed_at, fail_reason, priority FROM "rihanna_jobs" WHERE id = $1
        """,
        [id]
      )

    case Rihanna.Job.from_sql(rows) do
      [job] -> job
      [] -> nil
    end
  end

  @test_term {Kernel, :+, [1, 1]}

  def insert_job(pg, :ready_to_run) do
    result =
      Postgrex.query!(
        pg,
        """
          INSERT INTO "rihanna_jobs" (term, enqueued_at)
          VALUES ($1, '2018-01-01')
          RETURNING id, term, enqueued_at, due_at, failed_at, fail_reason, priority
        """,
        [:erlang.term_to_binary(@test_term)]
      )

    [job] = Rihanna.Job.from_sql(result.rows)

    job
  end

  def insert_job(pg, :ready_to_run_highest_priority) do
    result =
      Postgrex.query!(
        pg,
        """
          INSERT INTO "rihanna_jobs" (term, enqueued_at, priority)
          VALUES ($1, '2018-01-01', 1)
          RETURNING id, term, enqueued_at, due_at, failed_at, fail_reason, priority
        """,
        [:erlang.term_to_binary(@test_term)]
      )

    [job] = Rihanna.Job.from_sql(result.rows)

    job
  end

  # Insert a job scheduled for one minute in the future.
  def insert_job(pg, :scheduled_at) do
    result =
      Postgrex.query!(
        pg,
        """
          INSERT INTO "rihanna_jobs" (term, enqueued_at, due_at)
          VALUES ($1, '2018-01-01', now() + interval '1 minute')
          RETURNING id, term, enqueued_at, due_at, failed_at, fail_reason, priority
        """,
        [:erlang.term_to_binary(@test_term)]
      )

    [job] = Rihanna.Job.from_sql(result.rows)

    job
  end

  # Insert a job scheduled for now.
  def insert_job(pg, :schedule_due) do
    result =
      Postgrex.query!(
        pg,
        """
          INSERT INTO "rihanna_jobs" (term, enqueued_at, due_at)
          VALUES ($1, '2018-01-01', now())
          RETURNING id, term, enqueued_at, due_at, failed_at, fail_reason, priority
        """,
        [:erlang.term_to_binary(@test_term)]
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
          term,
          enqueued_at,
          failed_at,
          fail_reason
        )
        VALUES ($1, '2018-01-01', '2018-01-02', 'Kaboom!')
        RETURNING id, term, enqueued_at, due_at, failed_at, fail_reason, priority
        """,
        [:erlang.term_to_binary(@test_term)]
      )

    [job] = Rihanna.Job.from_sql(result.rows)

    job
  end
end
