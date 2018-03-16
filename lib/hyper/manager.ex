defmodule Hyper.Manager do
  use GenServer
  import Ecto.Query

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    Process.send(self(), :poll, [])
    {:ok, state}
  end

  def handle_info(:poll, state) do
    # Read all ready_to_run jobs from the queue and spin off tasks to execute
    # each one

    ready_to_run_jobs = NestDB.Repo.all(Hyper.Job, where: [state: "ready_to_run"])
    Enum.each(ready_to_run_jobs, fn job ->
      IO.inspect("locking job in pid #{inspect(self)}")
      # Lock all jobs with SQL query
      lock_for_running(job)
      # Fire and forget each job (Task.start)
      Hyper.Worker.start(job)
    end)

    # sweep for expired (failed) jobs
    NestDB.Repo.update_all(
      from(
        j in Hyper.Job,
        where: j.state == "in_progress",
        where: j.expires_at < fragment("NOW()")
      ),
      [
        set: [
          state: "failed"
        ]
      ]
    )

    schedule_poll()
    {:noreply, state}
  end

  def lock_for_running(job) do
    now = DateTime.utc_now
    result = NestDB.Repo.update_all(
      from(
        j in Hyper.Job,
        where: j.id == ^job.id,
        where: j.state == "ready_to_run"
      ),
      [
        set: [
          state: "in_progress",
          expires_at: Hyper.Job.expires_at(now),
          updated_at: now
        ]
      ],
      returning: true
    )

    case result do
      {0, _} -> {:error, :job_not_found}
      {1, [job]} ->
        {:ok, job}
    end
  end


  defp schedule_poll() do
    Process.send_after(self(), :poll, poll_period())
  end

  defp poll_period() do
    # :timer.minutes(1) + antialias()
    :timer.seconds(15)
  end

  # To prevent multiple workers started simultaneously from hitting the database
  # at similar times, we add a small random variance to the poll interval
  defp antialias() do
    round((:rand.uniform - 0.5) * :timer.seconds(5))
  end
end
