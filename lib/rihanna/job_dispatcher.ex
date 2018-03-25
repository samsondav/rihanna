defmodule Rihanna.JobDispatcher do # TODO: Is WorkerPool a better name?
  use GenServer
  require Logger

  @max_concurrency 25 # maximum number of simultaneously executing tasks for this dispatcher
  # @poll_interval 100 # milliseconds
  @poll_interval 10_000 # milliseconds
  @pg_advisory_class_id 42 # the class ID to which we "scope" our advisory locks

  def start_link(config, opts) do
    # NOTE: It is important that a new pg session is started if the
    # JobDispatcher dies since otherwise we may leave dangling locks in the zombie
    # pg process
    db = Keyword.get(config, :db)

    {:ok, pg} = Postgrex.start_link(db)

    GenServer.start_link(__MODULE__, %{working: %{}, pg: pg}, opts)
  end

  # state:
  # %{
  #     ref => task1,
  #     ref => task2,
  # }
  #
  def init(state) do
    Process.send(self(), :poll, [])
    {:ok, state}
  end

  def handle_info(:poll, state = %{working: working, pg: pg}) do
    # Fill the pipeline with as much work as we can get
    available_concurrency = @max_concurrency - Enum.count(working)

    working = Enum.reduce_while(1..available_concurrency, working, fn _, acc ->
      case lock_one_job(pg) do
        nil ->
          {:halt, acc}
        job ->
          IO.puts "locked #{job.id}"
          task = spawn_supervised_task(job)
          {:cont, Map.put(acc, task.ref, job)}
      end
    end)

    Process.send_after(self(), :poll, @poll_interval)

    {:noreply, Map.put(state, :working, working)}
  end

  def handle_info({ref, result}, state = %{pg: pg, working: working}) do
    Process.demonitor(ref, [:flush]) # Flush guarantees that DOWN message will be received before demonitoring

    {job, working} = Map.pop(working, ref)
    IO.puts "Job #{job.id} completed successfully by #{inspect(ref)} with result: #{result}"

    Rihanna.Job.mark_successful(job.id)
    release_lock(pg, job.id)

    # Attempt to lock ONE new job to replace
    working = case lock_one_job(pg) do
      nil ->
        working
      job ->
        task = spawn_supervised_task(job)
        Map.put(working, task.ref, job)
    end

    {:noreply, Map.put(state, :working, working)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state = %{pg: pg, working: working}) do
    {job, working} = Map.pop(working, ref)
    IO.puts "Job #{job.id} failed in #{inspect(ref)}!"

    Rihanna.Job.mark_failed(job.id, DateTime.utc_now(), Exception.format_exit(reason))
    release_lock(pg, job.id)


    # Attempt to lock ONE new job to replace
    working = case lock_one_job(pg) do
      nil ->
        working
      job ->
        task = spawn_supervised_task(job)
        Map.put(working, task.ref, job)
    end

    {:noreply, Map.put(state, :working, working)}
  end

  def spawn_supervised_task(job) do
    Task.Supervisor.async_nolink(Rihanna.TaskSupervisor, fn ->
      {mod, fun, args} = job.mfa
      apply(mod, fun, args)
    end)
  end

  defp release_lock(pg, id) do
    %{rows: [[true]]} = Postgrex.query!(pg, """
      SELECT pg_advisory_unlock($1);
    """, [id])

    :ok
  end

  defp lock_one_job(pg) do
    case lock_n_jobs(pg, 1) do
      [job] ->
        job
      [] ->
        nil
    end
  end

  defp lock_n_jobs(pg, n) do
    lock_jobs = """
      WITH RECURSIVE jobs AS (
        SELECT (j).*, pg_try_advisory_lock((j).id) AS locked
        FROM (
          SELECT j
          FROM #{Rihanna.Job.table()} AS j
          LEFT OUTER JOIN locks_held_by_this_session lh
          ON lh.id = j.id
          WHERE lh.id IS NULL
          AND state = 'ready_to_run'
          ORDER BY enqueued_at, j.id
          LIMIT 1
        ) AS t1
        UNION ALL (
          SELECT (j).*, pg_try_advisory_lock((j).id) AS locked
          FROM (
            SELECT (
              SELECT j
              FROM #{Rihanna.Job.table()} AS j
              LEFT OUTER JOIN locks_held_by_this_session lh
              ON lh.id = j.id
              WHERE lh.id IS NULL
              AND state = 'ready_to_run'
              AND (j.enqueued_at, j.id) > (jobs.enqueued_at, jobs.id)
              ORDER BY enqueued_at, j.id
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
        AND pl.pid = pg_backend_pid()
      )
      SELECT id, mfa, enqueued_at, updated_at, state, heartbeat_at, failed_at, fail_reason
      FROM jobs
      WHERE locked
      LIMIT $1;
    """

    IO.puts lock_jobs
    IO.puts n

    %{rows: rows} = Postgrex.query!(pg, lock_jobs, [n])

    Rihanna.Job.from_sql(rows)
  end
end
