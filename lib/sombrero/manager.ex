defmodule Sombrero.Manager do
  use GenServer
  import Ecto.Query

  @baseline_poll_interval :timer.seconds(60)

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    Process.send(self(), :poll, [])
    {:ok, state}
  end

  def handle_info(:poll, state) do
    # TODO: Need to LISTEN to pg_notify to enqueue jobs immediately
    # Then we can use the poll as a failsafe
    fire_off_ready_to_run_jobs()
    sweep_for_expired_jobs()

    schedule_poll()
    {:noreply, state}
  end

  defp fire_off_ready_to_run_jobs() do
    # Read all ready_to_run jobs from the queue and spin off tasks to execute
    # each one

    ready_to_run_jobs = Sombrero.Repo.all(
      from(
        Sombrero.Job,
        where: [state: "ready_to_run"]
      )
    )

    Enum.each(ready_to_run_jobs, fn job ->
      IO.inspect("locking job in pid #{inspect(self)}")
      # Lock all jobs with SQL query
      lock_for_running(job)
      # Fire and forget each job (Task.start)
      Sombrero.Worker.start(job)
    end)
  end

  defp sweep_for_expired_jobs() do
    Sombrero.Repo.update_all(
      from(
        j in Sombrero.Job,
        where: j.state == "in_progress",
        where: j.expires_at < fragment("NOW()")
      ),
      set: [
        state: "failed"
      ]
    )
  end

  def lock_for_running(job) do
    now = DateTime.utc_now()

    result =
      Sombrero.Repo.update_all(
        from(
          j in Sombrero.Job,
          where: j.id == ^job.id,
          where: j.state == "ready_to_run"
        ),
        [
          set: [
            state: "in_progress",
            expires_at: Sombrero.Job.expires_at(now),
            updated_at: now
          ]
        ],
        returning: true
      )

    case result do
      {0, _} ->
        {:error, :job_not_found}

      {1, [job]} ->
        {:ok, job}
    end
  end

  defp schedule_poll() do
    Process.send_after(self(), :poll, poll_period())
  end

  defp poll_period() do
    @baseline_poll_interval + antialias()
  end

  # To prevent multiple workers started simultaneously from hitting the database
  # at similar times, we add a small random variance to the poll interval
  defp antialias() do
    round((:rand.uniform() - 0.5) * :timer.seconds(5))
  end
end
