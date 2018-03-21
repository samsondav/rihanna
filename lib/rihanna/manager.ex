defmodule Rihanna.Producer do
  use GenServer
  require Logger
  import Ecto.Query

  @baseline_poll_interval :timer.seconds(60)

  def start_link(opts) do
    state = Enum.into(opts, %{})
    GenServer.start_link(__MODULE__, state)
  end

  def init(state) do
    {:ok, _ref} = Postgrex.Notifications.listen(Rihanna.PGNotifier, "insert_job")

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
        # this is fine, another process already claimed it
        :noop
    end

    {:noreply, state}
  end

  defp fire_off_ready_to_run_jobs() do
    # Read all ready_to_run jobs from the queue and spin off tasks to execute
    # each one

    ready_to_run_jobs =
      Rihanna.Repo.all(
        from(
          Rihanna.Job,
          where: [state: "ready_to_run"],
          select: [:id]
        )
      )

    # FIXME: This is not particularly efficient since it issues N updates where
    # N is the number of ready to run jobs
    Enum.each(ready_to_run_jobs, fn %{id: id} ->
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

    Rihanna.Repo.update_all(
      from(
        j in Rihanna.Job,
        where: j.state == "in_progress",
        where: j.expires_at < ^now
      ),
      set: [
        state: "failed",
        expires_at: nil,
        failed_at: now,
        fail_reason: "Unknown: worker went AWOL"
      ]
    )
  end

  def lock_for_running(job_id) do
    now = DateTime.utc_now()

    result =
      Rihanna.Repo.update_all(
        from(
          j in Rihanna.Job,
          where: j.id == ^job_id,
          where: j.state == "ready_to_run"
        ),
        [
          set: [
            state: "in_progress",
            expires_at: Rihanna.Job.expires_at(now),
            updated_at: now
          ]
        ],
        returning: true
      )

    case result do
      {1, [job]} ->
        Logger.debug("Got lock for job #{job.id} in pid #{inspect(self())}")
        {:ok, job}

      {0, _} ->
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
