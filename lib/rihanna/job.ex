defmodule Rihanna.Job do
  require Logger

  @type result :: any
  @type reason :: any
  @type t :: %__MODULE__{}

  @callback perform(arg :: any) :: :ok | {:ok, result} | :error | {:error, reason}

  @moduledoc """
  A behaviour for Rihanna jobs.

  You must implement `c:Rihanna.Job.perform/1` in your job, and it must return
  one of the following values:

    - `:ok`
    - `{:ok, result}`
    - `:error`
    - `{:error, reason}`

  You can define your job like the example below:

  ```
  defmodule MyApp.MyJob do
    @behaviour Rihanna.Job

    # NOTE: `perform/1` is a required callback. It takes exactly one argument. To
    # pass multiple arguments, wrap them in a list and destructure in the
    # function head as in this example
    def perform([arg1, arg2]) do
      success? = do_some_work(arg1, arg2)

      if success? do
        # job completed successfully
        :ok
      else
        # job execution failed
        {:error, :failed}
      end
    end
  end

  """

  @fields [
    :id,
    :term,
    :enqueued_at,
    :due_at,
    :failed_at,
    :fail_reason
  ]

  defstruct @fields

  @doc false
  def start(job) do
    GenServer.call(Rihanna.JobManager, job)
  end

  @doc false
  def enqueue(term, due_at \\ nil) do
    serialized_term = :erlang.term_to_binary(term)

    now = DateTime.utc_now()

    %{rows: [job]} =
      Postgrex.query!(
        Rihanna.Job.Postgrex,
        """
          INSERT INTO "#{table()}" (term, enqueued_at, due_at)
          VALUES ($1, $2, $3)
          RETURNING #{sql_fields()}
        """,
        [serialized_term, now, due_at]
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
        due_at,
        failed_at,
        fail_reason
      ]) do
    %__MODULE__{
      id: id,
      term: :erlang.binary_to_term(serialized_term),
      enqueued_at: enqueued_at,
      due_at: due_at,
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
    lock(pg, [])
  end

  @doc false
  def lock(pg, exclude_ids) when is_pid(pg) and is_list(exclude_ids) do
    case lock(pg, 1, exclude_ids) do
      [job] ->
        job

      [] ->
        nil
    end
  end

  # This query is at the heart of the how the dispatcher pulls jobs from the queue.
  #
  # It is heavily inspired by a similar query in Que: https://github.com/chanks/que/blob/0.x/lib/que/sql.rb#L5
  #
  # There are some minor additions:
  #
  # I could not find any easy way to check if one particular advisory lock is
  # already held by the current session, so each dispatcher must pass in a list
  # of ids for jobs which are currently already working so those can be excluded.
  #
  # We also use a FOR UPDATE SKIP LOCKED since this causes the query to skip
  # jobs that were completed (and deleted) by another session in the time since
  # the table snapshot was taken. In rare cases under high concurrency levels,
  # leaving this out can result in double executions.
  @doc false
  def lock(pg, n) do
    lock(pg, n, [])
  end

  @doc false
  def lock(_, 0, _) do
    []
  end

  @doc false
  def lock(pg, n, exclude_ids)
      when is_pid(pg) and is_integer(n) and n > 0 and is_list(exclude_ids) do
    table = table()

    lock_jobs = """
      WITH RECURSIVE jobs AS (
        SELECT (j).*, pg_try_advisory_lock($1::integer, (j).id) AS locked
        FROM (
          SELECT j
          FROM #{table} AS j
          WHERE NOT (id = ANY($3))
          AND failed_at IS NULL
          ORDER BY enqueued_at, j.id
          FOR UPDATE OF j SKIP LOCKED
          LIMIT 1
        ) AS t1
        UNION ALL (
          SELECT (j).*, pg_try_advisory_lock($1::integer, (j).id) AS locked
          FROM (
            SELECT (
              SELECT j
              FROM #{table} AS j
              WHERE NOT (id = ANY($3))
              AND failed_at IS NULL
              AND (j.enqueued_at, j.id) > (jobs.enqueued_at, jobs.id)
              ORDER BY enqueued_at, j.id
              FOR UPDATE OF j SKIP LOCKED
              LIMIT 1
            ) AS j
            FROM jobs
            WHERE jobs.id IS NOT NULL
            LIMIT 1
          ) AS t1
        )
      )
      SELECT id, term, enqueued_at, due_at, failed_at, fail_reason
      FROM jobs
      WHERE locked
      LIMIT $2
    """

    %{rows: rows} = Postgrex.query!(pg, lock_jobs, [classid(), n, exclude_ids])

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

  @doc """
  The name of the jobs table.
  """
  @spec table() :: String.t()
  def table() do
    Rihanna.Config.jobs_table_name()
  end

  @doc false
  def classid() do
    Rihanna.Config.pg_advisory_lock_class_id()
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

  defp sql_fields() do
    @fields
    |> Enum.map(&to_string/1)
    |> Enum.join(", ")
  end
end
