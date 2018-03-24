defmodule Rihanna.Producer do
  use GenServer
  require Logger
  alias Rihanna.Job

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

  # NOTE: Should we match on this pid and ref?
  def handle_info(msg = {:notification, _pid, _ref, "insert_job", job_id}, state) do
    Logger.debug("Got notification: #{inspect(msg)}")

    fire_off_job(job_id)

    {:noreply, state}
  end

  defp fire_off_ready_to_run_jobs() do
    # Read all ready_to_run jobs from the queue and spin off tasks to execute
    # each one
    #
    # FIXME: This is not particularly efficient since it issues N updates where
    # N is the number of ready to run jobs
    #
    # FIXME: Neither does it place any kind of limits on the number of workers started.
    # i.e. if you read 10,000 jobs, then 10,000 workers will be concurrently spawned
    # to handle them
    Enum.each(Job.ready_to_run_ids(), fn job_id ->
      fire_off_job(job_id)
    end)
  end

  defp fire_off_job(job_id) do
    case Job.lock_for_running(job_id) do
      {:ok, job} ->
        Job.start(job)

      {:error, :missed_lock} ->
        :noop
    end
  end

  defp sweep_for_expired_jobs() do
    now = DateTime.utc_now()

    assume_dead =
      now
      |> DateTime.to_unix()
      |> Kernel.-(@grace_time_seconds)
      |> DateTime.from_unix!()

    Job.sweep_for_expired(now, assume_dead)
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
