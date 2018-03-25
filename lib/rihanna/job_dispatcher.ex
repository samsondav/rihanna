defmodule Identity do
  def identity(x) do
    x
  end
end

defmodule Flusher do
  def count_messages do
    Process.put(:messages, [])
    do_count_messages
    length(Process.get(:messages))
  end
  defp do_count_messages do
    receive do
      msg ->
        Process.put(:messages, [msg | Process.get(:messages)])
        do_count_messages
      after
        0 -> :ok
    end
  end
end

defmodule Timer do
  use GenServer

  def start_link(db) do
    {:ok, pg} = Postgrex.start_link(db)

    GenServer.start_link(__MODULE__, %{pg: pg, start: :erlang.timestamp(), reported: false}, [])
  end

  def init(state) do
    IO.puts "Timer starting"
    Process.send(self(), :poll, [])
    {:ok, state}
  end

  def handle_info(:poll, state = %{pg: pg, start: start, reported: reported}) do
    now = :erlang.timestamp
    %{num_rows: count} = Postgrex.query!(pg, "SELECT * FROM rihanna_jobs LIMIT 1", [])
    if count == 0 and not reported do
      IO.puts "DONE in #{:timer.now_diff(now, start) / 1000}ms"
      state = Map.put(state, :reported, true)
    end
    Process.send_after(self(), :poll, 100)

    {:noreply, state}
  end
end

defmodule Rihanna.JobDispatcher do # TODO: Is WorkerPool a better name?
  use GenServer
  require Logger

  @max_concurrency 25 # maximum number of simultaneously executing tasks for this dispatcher
  # @poll_interval 100 # milliseconds
  @poll_interval 100 # milliseconds
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

    jobs = lock_jobs(pg, available_concurrency)

    {us, working} = :timer.tc fn ->
      for job <- jobs, into: working do
        task = spawn_supervised_task(job)
        {task.ref, job}
      end
    end

    if Enum.any?(jobs) do
      # Logger.debug("Spawned #{length(jobs)} in #{us / 1000}ms")
    end

    # if Enum.any?(working) do
    #   # IO.puts("TOOK:  to spawn tasks")
    # end
    #     working = Enum.reduce_while(1..available_concurrency, working, fn _, acc ->
    #   case lock_one_job(pg, acc) do
    #     nil ->
    #       {:halt, acc}
    #     job ->
    #       postgrex_connection_id = Postgrex.query!(pg, "SELECT 1",[]).connection_id
    #       IO.puts "#{self() |> inspect} locked #{job.id} - pg pid was #{inspect pg}, connection_id #{postgrex_connection_id}"
    #       task = spawn_supervised_task(job)
    #       Process.send(elem(job.mfa, 2) |> hd, {self(), job.id}, [])
    #       {:cont, Map.put(acc, task.ref, job)}
    #   end
    # end)

    Process.send_after(self(), :poll, @poll_interval + :rand.uniform(50))

    {:noreply, Map.put(state, :working, working)}
  end

  def handle_info({ref, result}, state = %{pg: pg, working: working}) do
    Process.demonitor(ref, [:flush]) # Flush guarantees that DOWN message will be received before demonitoring

    # Logger.debug "#{inspect(ref)} yielded #{result}"

    {job, working} = Map.pop(working, ref)

    # IO.puts "Job #{job.id} completed successfully by #{inspect(ref)} with result: #{result}"

    # Rihanna.Job.mark_successful(job.id)
    Postgrex.query!(pg, "DELETE FROM rihanna_jobs WHERE id = $1", [job.id])
    release_lock(pg, job.id)


    # Attempt to lock ONE new job to replace
    # working = case lock_one_job(pg) do
    #   nil ->
    #     working
    #   job ->
    #     task = spawn_supervised_task(job)
    #     Map.put(working, task.ref, job)
    # end

    state = Map.put(state, :working, working)

    {:noreply, state}
  end

  # def handle_info({:DOWN, ref, :process, _pid, reason}, state = %{pg: pg, working: working}) do
  #   {job, working} = Map.pop(working, ref)
  #   # IO.puts "Job #{job.id} failed in #{inspect(ref)}!"

  #   Rihanna.Job.mark_failed(job.id, DateTime.utc_now(), Exception.format_exit(reason))
  #   release_lock(pg, job.id)

  #   # Attempt to lock ONE new job to replace
  #   working = case lock_one_job(pg, working) do
  #     nil ->
  #       working
  #     job ->
  #       task = spawn_supervised_task(job)
  #       Map.put(working, task.ref, job)
  #   end

  #   {:noreply, Map.put(state, :working, working)}
  # end

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
    case lock_jobs(pg, 1) do
      [job] ->
        job
      [] ->
        nil
    end
  end

  defp lock_jobs(pg, n) do
    lock_jobs = """
      WITH RECURSIVE jobs AS (
        SELECT (j).*, pg_try_advisory_lock((j).id) AS locked
        FROM (
          SELECT j
          FROM #{Rihanna.Job.table()} AS j
          LEFT OUTER JOIN locks_held_by_this_job_dispatcher lh
          ON lh.id = j.id
          WHERE lh.id IS NULL
          AND state = 'ready_to_run'
          ORDER BY enqueued_at, j.id
          FOR UPDATE SKIP LOCKED
          LIMIT 1
        ) AS t1
        UNION ALL (
          SELECT (j).*, pg_try_advisory_lock((j).id) AS locked
          FROM (
            SELECT (
              SELECT j
              FROM #{Rihanna.Job.table()} AS j
              LEFT OUTER JOIN locks_held_by_this_job_dispatcher lh
              ON lh.id = j.id
              WHERE lh.id IS NULL
              AND state = 'ready_to_run'
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
      locks_held_by_this_job_dispatcher AS (
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

    {execution_time, %{rows: rows}} = :timer.tc(fn ->
      Postgrex.query!(pg, lock_jobs, [n])
    end)

    if Enum.any?(rows) do
      # Logger.debug("Locking #{length(rows)} jobs took #{execution_time / 1000}ms")
    end

    Rihanna.Job.from_sql(rows)
  end
end
