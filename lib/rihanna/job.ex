defmodule Rihanna.Job do
  require Logger

  @type result :: any
  @type reason :: any

  @callback perform(arg :: any) :: :ok | {:ok, result} | {:error, reason}

  @moduledoc """
  Yea..... gonna write some
  """

  @fields [
    :id,
    :term,
    :enqueued_at,
    :failed_at,
    :fail_reason
  ]

  defstruct @fields

  def start(job) do
    GenServer.call(Rihanna.JobManager, job)
  end

  @doc false
  def enqueue(term) do
    serialized_term = :erlang.term_to_binary(term)

    now = DateTime.utc_now()

    %{rows: [job]} =
      Postgrex.query!(
        Rihanna.Job.Postgrex,
        """
          INSERT INTO "#{table()}" (term, enqueued_at)
          VALUES ($1, $2)
          RETURNING #{sql_fields()}
        """,
        [serialized_term, now]
      )

    {:ok, from_sql(job)}
  end

  @doc false
  def from_sql(rows = [row | _]) when is_list(rows) and is_list(row) do
    for row <- rows, do: from_sql(row)
  end

  @doc false
  def from_sql([
        id,
        serialized_term,
        enqueued_at,
        failed_at,
        fail_reason
      ]) do
    %__MODULE__{
      id: id,
      term: :erlang.binary_to_term(serialized_term),
      enqueued_at: enqueued_at,
      failed_at: failed_at,
      fail_reason: fail_reason
    }
  end

  @doc false
  def from_sql([]), do: []

  @doc false
  def retry_failed(pg \\ Rihanna.Job.Postgrex, job_id)
      when (is_pid(pg) or is_atom(pg)) and is_integer(job_id) do
    now = DateTime.utc_now()

    result =
      Postgrex.query!(
        pg,
        """
          UPDATE "#{table()}"
          SET
            failed_at = NULL,
            fail_reason = NULL,
            enqueued_at = $1
          WHERE
            failed_at IS NOT NULL AND id = $2
        """,
        [now, job_id]
      )

    case result.num_rows do
      0 ->
        {:error, :job_not_found}

      1 ->
        {:ok, :retried}
    end
  end

  @doc false
  def lock(pg) when is_pid(pg) do
    case lock(pg, 1) do
      [job] ->
        job

      [] ->
        nil
    end
  end

  # TODO: Write some documentation for this monster
  @doc false
  def lock(pg, n) when is_pid(pg) and is_integer(n) and n > 0 do
    table = table()

    lock_jobs = """
      WITH RECURSIVE jobs AS (
        SELECT (j).*, pg_try_advisory_lock($1::integer, (j).id) AS locked
        FROM (
          SELECT j
          FROM #{table} AS j
          LEFT OUTER JOIN locks_held_by_this_session lh
          ON lh.id = j.id
          WHERE lh.id IS NULL
          AND failed_at IS NULL
          ORDER BY enqueued_at, j.id
          FOR UPDATE SKIP LOCKED
          LIMIT 1
        ) AS t1
        UNION ALL (
          SELECT (j).*, pg_try_advisory_lock($1::integer, (j).id) AS locked
          FROM (
            SELECT (
              SELECT j
              FROM #{table} AS j
              LEFT OUTER JOIN locks_held_by_this_session lh
              ON lh.id = j.id
              WHERE lh.id IS NULL
              AND failed_at IS NULL
              AND (j.enqueued_at, j.id) > (jobs.enqueued_at, jobs.id)
              ORDER BY enqueued_at, j.id
              FOR UPDATE SKIP LOCKED
              LIMIT 1
            ) AS j
            FROM jobs
            WHERE jobs.id IS NOT NULL
            LIMIT 1
          ) AS t1
        )
      ),
      locks_held_by_this_session AS (
        SELECT objid AS id
        FROM pg_locks pl
        WHERE locktype = 'advisory'
        AND classid = $1
        AND pl.pid = pg_backend_pid()
      )
      SELECT id, term, enqueued_at, failed_at, fail_reason
      FROM jobs
      WHERE locked
      LIMIT $2;
    """

    %{rows: rows} = Postgrex.query!(pg, lock_jobs, [classid(), n])

    Rihanna.Job.from_sql(rows)
  end

  @doc false
  def mark_successful(pg, job_id) when is_pid(pg) and is_integer(job_id) do
    %{num_rows: num_rows} =
      Postgrex.query!(
        pg,
        """
          DELETE FROM "#{table()}"
          WHERE id = $1;
        """,
        [job_id]
      )

    release_lock(pg, job_id)

    {:ok, num_rows}
  end

  @doc false
  def mark_failed(pg, job_id, now, fail_reason) when is_pid(pg) and is_integer(job_id) do
    %{num_rows: num_rows} =
      Postgrex.query!(
        pg,
        """
          UPDATE "#{table()}"
          SET
            failed_at = $1,
            fail_reason = $2
          WHERE
            id = $3
        """,
        [now, fail_reason, job_id]
      )

    release_lock(pg, job_id)

    {:ok, num_rows}
  end

  defp release_lock(pg, job_id) when is_pid(pg) and is_integer(job_id) do
    %{rows: [[true]]} =
      Postgrex.query!(
        pg,
        """
          SELECT pg_advisory_unlock($1, $2);
        """,
        [classid(), job_id]
      )
  end

  @doc """
  The name of the jobs table.
  """
  def table() do
    Rihanna.Config.jobs_table_name()
  end

  @doc false
  def classid() do
    Rihanna.Config.pg_advisory_lock_class_id()
  end

  defp sql_fields() do
    @fields
    |> Enum.map(&to_string/1)
    |> Enum.join(", ")
  end
end
