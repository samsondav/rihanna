defmodule Rihanna.JobManager do
  use GenServer
  require Logger
  require Ecto.Query, as: Query

  # Issue heartbeat every half of grace time
  @hearbeat_interval round(:timer.seconds(Rihanna.Job.grace_time_seconds()) / 2)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  def init(state) do
    start_timer()
    {:ok, state}
  end

  def handle_call(job, _from, state) do
    %{mfa: {mod, fun, args}} = job
    task = Task.Supervisor.async_nolink(Rihanna.JobSupervisor, fn ->
      result = apply(mod, fun, args)
      success(job.id)
      result
    end)

    state = Map.put(state, task.ref, job)

    {:reply, :ok, state}
  end

  def handle_info({ref, _result}, state) do
    Process.demonitor(ref, [:flush])
    {_job, state} = Map.pop(state, ref)
    # job finished
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    {job, state} = Map.pop(state, ref)
    failure(job.id, reason)
    {:noreply, state}
  end

  def handle_info(:heartbeat, state) do
    job_ids = state
    |> Map.values()
    |> Enum.map(fn %{id: id} -> id end)

    Logger.debug("HEARTBEAT from #{inspect(self())} updating #{length(job_ids)} jobs")

    extend_expiry(job_ids)
    {:noreply, state}
  end

  defp extend_expiry(job_ids) do
    now = DateTime.utc_now()
    new_expiry = Rihanna.Job.expires_at(now)

    if Enum.any?(job_ids) do
      {_n, nil} =
        Rihanna.Repo.update_all(
          Query.from(
            j in Rihanna.Job,
            where: j.id in ^job_ids
          ),
          set: [
            expires_at: new_expiry,
            updated_at: now
          ]
        )
    end
  end

  defp success(job_id) do
    Rihanna.Repo.delete_all(
      Query.from(
        j in Rihanna.Job,
        where: j.id == ^job_id
      )
    )
  end

  defp failure(job_id, reason) do
    now = DateTime.utc_now()

    {1, nil} =
      Rihanna.Repo.update_all(
        Query.from(
          j in Rihanna.Job,
          where: j.id == ^job_id
        ),
        set: [
          state: "failed",
          failed_at: now,
          fail_reason: Exception.format_exit(reason),
          expires_at: nil,
          updated_at: now
        ]
      )
  end

  defp start_timer() do
    {:ok, _ref} = :timer.send_interval(@hearbeat_interval, :heartbeat)
  end
end
