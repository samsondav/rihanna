defmodule Rihanna.Producer do
  use GenServer
  require Logger

  @baseline_poll_interval :timer.seconds(60)

  # Time since last heartbeat that job will be assumed to have failed
  @grace_time_seconds 30
  def grace_time_seconds, do: @grace_time_seconds

  def start_link(opts) do
    state = Enum.into(opts, %{})
    GenServer.start_link(__MODULE__, state)
  end

  def init(state) do
    {:ok, _ref} = Postgrex.Notifications.listen(Rihanna.Postgrex.Notifications, "insert_job")

    Process.send(self(), :poll, [])
    {:ok, state}
  end

  def handle_info(:poll, state) do
    fire_off_ready_to_run_jobs()
    sweep_for_expired_jobs()

    schedule_poll()
    {:noreply, state}
  end

  # TODO: Should probably match on this pid and ref
  def handle_info(msg = {:notification, _pid, _ref, "insert_job", payload}, state) do
    Logger.debug("Got notification: #{inspect(msg)}")
    payload = Jason.decode!(payload)
    id = payload["id"]

    case lock_for_running(id) do
      {:ok, job} ->
        Rihanna.Job.start(job)

      {:error, :missed_lock} ->
        :noop
    end

    {:noreply, state}
  end

  defp fire_off_ready_to_run_jobs() do
    # Read all ready_to_run jobs from the queue and spin off tasks to execute
    # each one

    ready_to_run_job_ids =
      Rihanna.Job.query!("""
        SELECT id FROM "#{Rihanna.Job.table()}"
        WHERE state = 'ready_to_run'
        """, [])
      |> Map.fetch!(:rows)
      |> Enum.map(fn [id] when is_integer(id) -> id end)

    # FIXME: This is not particularly efficient since it issues N updates where
    # N is the number of ready to run jobs
    Enum.each(ready_to_run_job_ids, fn id ->
      case lock_for_running(id) do
        {:ok, job} ->
          Rihanna.Job.start(job)

        {:error, :missed_lock} ->
          :noop
      end
    end)
  end

  defp sweep_for_expired_jobs() do
    now = DateTime.utc_now()
    assume_dead = now
    |> DateTime.to_unix()
    |> Kernel.-(@grace_time_seconds)
    |> DateTime.from_unix!()

    Rihanna.Job.query!("""
      UPDATE "#{Rihanna.Job.table()}"
      SET
        state = "failed",
        heartbeat_at = NULL,
        failed_at = $1,
        fail_reason = 'Unknown: worker went AWOL'
      WHERE
        state = 'in_progress' AND j.heartbeat_at <= $2
      """, [now, assume_dead])
  end

  def lock_for_running(job_id) do
    now = DateTime.utc_now()

    result =
      Rihanna.Job.query!("""
        UPDATE "#{Rihanna.Job.table()}"
        SET
          state = 'in_progress',
          heartbeat_at = $1,
          updated_at = $1
        WHERE
          id = $2, state = 'ready_to_run'
        RETURNING
          #{Rihanna.Job.sql_fields()}
        """, [now, job_id])

    case result.num_rows do
      1 ->
        [job] = result.rows |> Rihanna.Job.from_sql
        Logger.debug("Got lock for job #{job.id} in pid #{inspect(self())}")
        {:ok, job}

      0 ->
        Logger.debug("Missed lock for job #{job_id} in pid #{inspect(self())}")
        {:error, :missed_lock}
    end
  end

  defp schedule_poll() do
    Process.send_after(self(), :poll, poll_interval())
  end

  defp poll_interval() do
    @baseline_poll_interval + antialias()
  end

  # To prevent multiple workers started simultaneously from hitting the database
  # at similar times, we add a small random variance to the poll interval
  defp antialias() do
    round((:rand.uniform() - 0.5) * :timer.seconds(5))
  end
end
