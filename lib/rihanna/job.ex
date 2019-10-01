defmodule Rihanna.Job do
  require Logger

  @type result :: any
  @type reason :: any
  @type arg :: any
  @type t :: %__MODULE__{}

  @callback perform(arg :: any) :: :ok | {:ok, result} | :error | {:error, reason}
  @callback after_error({:error, reason} | :error | Exception.t(), arg) :: any()

  @callback retry_at({:error, reason} | :error | Exception.t(), arg, pos_integer) ::
              {:ok, DateTime.t()} | :noop
  @callback priority() :: pos_integer()
  @optional_callbacks after_error: 2, retry_at: 3, priority: 0

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
  ```

  This behaviour allows you to tailor what you'd like to happen after your
  job either fails, or raises an exception.

  You can define an `after_error/2` method which will run before the job is
  placed on the failed job queue.

  If you don't define this callback, it will add it to the failed job queue
  without running anything.

  If you wish to re-enqueue a job to run at a different time, you can simply
  return `{:reenqueue, due_at}` where `due_at` is some DateTime timestamp.

  ```
  def after_error(failure_reason, args) do
    notify_someone(__MODULE__, failure_reason, args)
  end
  ```

  You can define a `retry_at/3` callback function. Returning `{:ok, due_at}`
  will schedule the job to run again at that time. Returning :noop (the default)
  proceeds with normal job failure behavior. The value of `attempts` counts up
  from 0, to allow backing off `due_at` to be calculated.

  ```
  def retry_at(_failure_reason, _args, attempts) when attempts < 3 do
    due_at = DateTime.add(DateTime.utc_now(), attempts * 5, :second)
    {:ok, due_at}
  end

  def retry_at(_failure_reason, _args, _attempts) do
    warn("Job failed after 3 attempts")
    :noop
  end
  ```

  You can define a `priority/0` function which will be called if no priority
  is set when a job is enqueued. It should return a single integer. A priority
  of 1 will be the highest priority, with larger numbers being run after.
  If you don't define this callback it will default to a priority of 50, in an
  attempt to have it run at a lower priority.

  ```
  def priority(), do: 2
  ```
  """

  @fields [
    :id,
    :term,
    :enqueued_at,
    :due_at,
    :failed_at,
    :fail_reason,
    :rihanna_internal_meta,
    :priority
  ]

  defstruct @fields

  @sql_fields @fields
              |> Enum.map(&to_string/1)
              |> Enum.join(", ")

  @select_fields_for_recursive_lock_query @fields
                                          |> Enum.map(fn field ->
                                            "(j).#{field}"
                                          end)
                                          |> Enum.join(", ")

  @default_priority 50

  @doc false
  def start(job) do
    GenServer.call(Rihanna.JobManager, job)
  end

  @doc false
  def enqueue(term, opts \\ %{}) do
    serialized_term = :erlang.term_to_binary(term)

    # Fetch job module if it is a Rihanna.Job
    job_module =
      case term do
        {m, _args} -> m
        _ -> nil
      end

    priority = opts[:priority] || priority(job_module)

    now = DateTime.utc_now()

    result =
      producer_query(
        """
          INSERT INTO "#{table()}" (term, enqueued_at, due_at, priority)
          VALUES ($1, $2, $3, $4)
          RETURNING #{@sql_fields}
        """,
        [serialized_term, now, opts[:due_at], priority]
      )

    case result do
      {:ok, %Postgrex.Result{rows: [job]}} ->
        :telemetry.execute([:rihanna, :job, :enqueued], %{}, %{job_id: job |> hd, count: 1})
        {:ok, from_sql(job)}

      {:error, %Postgrex.Error{postgres: %{pg_code: "42P01"}}} ->
        # Undefined table error (e.g. `rihanna_jobs` table missing), warn user
        # to create their Rihanna jobs table
        Rihanna.Migration.raise_jobs_table_missing!()

      {:error, %Postgrex.Error{postgres: %{pg_code: "42703"}}} ->
        # Undefined column error (e.g. `due_at` missing), warn user to upgrade
        # their Rihanna jobs table
        Rihanna.Migration.raise_upgrade_required!()

      {:error, err} ->
        raise err
    end
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
        fail_reason,
        rihanna_internal_meta,
        priority
      ]) do
    %__MODULE__{
      id: id,
      term: :erlang.binary_to_term(serialized_term),
      enqueued_at: enqueued_at,
      due_at: due_at,
      failed_at: failed_at,
      fail_reason: fail_reason,
      rihanna_internal_meta: rihanna_internal_meta,
      priority: priority
    }
  end

  @doc false
  def from_sql([]), do: []

  @doc false
  def retry_failed(job_id) when is_integer(job_id) do
    now = DateTime.utc_now()

    {:ok, result} =
      producer_query(
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
  def delete_by(opts) do
    ids_to_delete =
      opts
      |> filter_term_list()
      |> Enum.join(",")

    if ids_to_delete != "" do
      case producer_query(
             """
                DELETE FROM "#{table()}"
                WHERE id IN (#{ids_to_delete})
             """,
             []
           ) do
        {:ok, %Postgrex.Result{num_rows: 0}} ->
          {:error, :job_not_found}

        {:ok, %Postgrex.Result{num_rows: n}} ->
          :telemetry.execute([:rihanna, :job, :deleted], %{}, %{count: n})
          {:ok, :deleted}

        error ->
          error
      end
    else
      {:error, :job_not_found}
    end
  end

  defp filter_term_list(mod: mod, fun: fun) when not is_nil(mod) and not is_nil(fun) do
    Enum.flat_map(retrieve_all_jobs(), fn [id, binary] ->
      term = :erlang.binary_to_term(binary)

      if match?({^mod, ^fun, _}, term) or match?({^mod, ^fun}, term) do
        [id]
      else
        []
      end
    end)
  end

  defp filter_term_list(mod: mod) when not is_nil(mod) do
    Enum.flat_map(retrieve_all_jobs(), fn [id, binary] ->
      term = :erlang.binary_to_term(binary)

      if match?({^mod, _, _}, term) or match?({^mod, _}, term) do
        [id]
      else
        []
      end
    end)
  end

  defp filter_term_list(fun: fun) when not is_nil(fun) do
    Enum.flat_map(retrieve_all_jobs(), fn [id, binary] ->
      term = :erlang.binary_to_term(binary)

      if match?({_, ^fun, _}, term) or match?({_, ^fun}, term) do
        [id]
      else
        []
      end
    end)
  end

  defp retrieve_all_jobs do
    {:ok, result} =
      producer_query(
        """
          SELECT id, term
          FROM "#{table()}"
        """,
        []
      )

    result.rows
  end

  def delete(job_id) do
    result =
      producer_query(
        """
          DELETE FROM "#{table()}"
          WHERE
            id = $1
          RETURNING #{@sql_fields}
        """,
        [job_id]
      )

    case result do
      {:ok, %Postgrex.Result{rows: [job]}} ->
        :telemetry.execute([:rihanna, :job, :deleted], %{}, %{job_id: job_id, count: 1})
        {:ok, from_sql(job)}

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        {:error, :job_not_found}
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

    # `due_at` NULLS FIRST ensures `enqueued_at` is respected when `due_at` is unset
    lock_jobs = """
      WITH RECURSIVE jobs AS (
        SELECT #{@select_fields_for_recursive_lock_query}, pg_try_advisory_lock($1::integer, (j).id) AS locked
        FROM (
          SELECT j
          FROM #{table} AS j
          WHERE NOT (id = ANY($3))
          AND (due_at IS NULL OR due_at <= now())
          AND failed_at IS NULL
          ORDER BY priority, due_at NULLS FIRST, enqueued_at, j.id
          FOR UPDATE OF j SKIP LOCKED
          LIMIT 1
        ) AS t1
        UNION ALL (
          SELECT  #{@select_fields_for_recursive_lock_query}, pg_try_advisory_lock($1::integer, (j).id) AS locked
          FROM (
            SELECT (
              SELECT j
              FROM #{table} AS j
              WHERE NOT (id = ANY($3))
              AND (due_at IS NULL OR due_at <= now())
              AND failed_at IS NULL
              AND (j.enqueued_at, j.id) > (jobs.enqueued_at, jobs.id)
              ORDER BY priority, due_at NULLS FIRST, enqueued_at, j.id
              FOR UPDATE OF j SKIP LOCKED
              LIMIT 1
            ) AS j
            FROM jobs
            WHERE jobs.id IS NOT NULL
            LIMIT 1
          ) AS t1
        )
      )
      SELECT #{@sql_fields}
      FROM jobs
      WHERE locked
      LIMIT $2
    """

    %{rows: rows, num_rows: num_rows} =
      Postgrex.query!(pg, lock_jobs, [classid(), n, exclude_ids])

    if num_rows > 0 do
      :telemetry.execute([:rihanna, :job, :locked], %{}, %{count: num_rows})
    end

    Rihanna.Job.from_sql(rows)
  end

  @doc false
  def mark_successful(pg, job_id) when is_pid(pg) and is_integer(job_id) do
    :telemetry.execute([:rihanna, :job, :succeeded], %{}, %{job_id: job_id, count: 1})

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
    :telemetry.execute([:rihanna, :job, :failed], %{}, %{job_id: job_id, count: 1})

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

  def mark_reenqueued(pg, job_id, due_at) when is_pid(pg) and is_integer(job_id) do
    :telemetry.execute([:rihanna, :job, :reenqueued], %{}, %{job_id: job_id, count: 1})

    %{num_rows: num_rows} =
      Postgrex.query!(
        pg,
        """
          UPDATE "#{table()}"
          SET
            due_at = $1
          WHERE
            id = $2
        """,
        [due_at, job_id]
      )

    release_lock(pg, job_id)

    {:ok, num_rows}
  end

  @doc """
  Update attempts and set due_at datetime
  """
  def mark_retried(pg, job_id, due_at) when is_pid(pg) and is_integer(job_id) do
    :telemetry.execute([:rihanna, :job, :retried], %{}, %{job_id: job_id, count: 1})

    %{num_rows: num_rows} =
      Postgrex.query!(
        pg,
        """
          UPDATE "#{table()}"
          SET
            due_at = $1,
            rihanna_internal_meta = jsonb_set(rihanna_internal_meta, '{attempts}', (
              COALESCE(rihanna_internal_meta->>'attempts','0')::int + 1
            )::text::jsonb)
          WHERE
            id = $2
        """,
        [due_at, job_id]
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
    :telemetry.execute([:rihanna, :job, :released], %{}, %{job_id: job_id, count: 1})

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
  Checks if a job implements `priority` callback and runs it.

  A lower value means a higher job priority. Has a default of 50,
  a very low priority, to prevent new jobs from running before
  higher priority jobs, when no priority is set.
  """
  def priority(nil), do: @default_priority

  def priority(job_module) do
    if :erlang.function_exported(job_module, :priority, 0) do
      job_module.priority()
    else
      @default_priority
    end
  end

  @doc """
  Checks whether a job implemented the `after_error` callback and runs it if it
  does.
  """
  def after_error(job_module, reason, arg) do
    if :erlang.function_exported(job_module, :after_error, 2) do
      # If they implemented the behaviour, there will only ever be one arg
      try do
        job_module.after_error(reason, arg)
      rescue
        exception ->
          Logger.warn(
            """
            [Rihanna] After error callback failed
            Got an unexpected error while trying to run the `after_error` callback.
            Check your `#{inspect(job_module)}.after_error/2` callback and make sure it doesn’t raise.
            Exception: #{inspect(exception)}
            Arg1: #{inspect(reason)}
            Arg2: #{inspect(arg)}
            """,
            exception: exception,
            job_arguments: arg,
            job_failure_reason: reason,
            job_module: job_module
          )

          :noop
      end
    end
  end

  @doc """
  Checks when a job should be retried at
  """
  def retry_at(job_module, reason, arg, attempts) do
    if :erlang.function_exported(job_module, :retry_at, 3) do
      try do
        job_module.retry_at(reason, arg, attempts || 0)
      rescue
        exception ->
          Logger.warn(
            """
            [Rihanna] retry_at/4 callback failed
            Got an unexpected error while trying to run the `retry_at` callback.
            Check your `#{inspect(job_module)}.retry_at/2` callback and make sure it doesn’t raise.
            Exception: #{inspect(exception)}
            Arg1: #{inspect(reason)}
            Arg2: #{inspect(arg)}
            """,
            exception: exception,
            job_arguments: arg,
            job_failure_reason: reason,
            job_module: job_module
          )

          :noop
      end
    else
      :noop
    end
  end

  # Some operations can use the shared database connection as they don't use locks
  defp producer_query(query, args) do
    producer_query(Rihanna.Config.producer_postgres_connection(), query, args)
  end

  if Code.ensure_compiled?(Ecto) do
    defp producer_query({Ecto, repo}, query, args) do
      Ecto.Adapters.SQL.query(repo, query, args)
    end
  end

  defp producer_query({Postgrex, conn}, query, args) do
    Postgrex.query(conn, query, args)
  end
end
