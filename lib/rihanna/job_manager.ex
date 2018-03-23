defmodule Rihanna.JobManager do
  use GenServer
  require Logger

  # Wait a maximum of half of grace time to issue a new heartbeat
  @hearbeat_interval round(:timer.seconds(Rihanna.Producer.grace_time_seconds()) / 2)

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

    if Enum.any?(job_ids) do
      Rihanna.Job.query!("""
        UPDATE "#{Rihanna.Job.table()}"
        SET
          heartbeat_at = $1,
          updated_at = $1
        WHERE
          id IN $2
      """, [now, job_ids]
      )
    end
  end

  defp success(job_id) do
    Rihanna.Job.query!("""
      DELETE FROM "#{Rihanna.Job.table()}"
      WHERE id = $1
    """, [job_id] )
  end

  defp failure(job_id, reason) do
    now = DateTime.utc_now()

    Rihanna.Job.query!("""
      UPDATE "#{Rihanna.Job.table()}"
      SET
        state = 'failed',
        failed_at = $1,
        fail_reason = $2,
        heartbeat_at = NULL,
        updated_at: $1
      WHERE
        id = $3
    """, [now, Exception.format_exit(reason), job_id])
  end

  defp start_timer() do
    {:ok, _ref} = :timer.send_interval(@hearbeat_interval, :heartbeat)
  end
end
