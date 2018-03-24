defmodule Rihanna.JobManager do
  use GenServer
  require Logger

  # Wait a maximum of half of grace time to issue a new heartbeat
  @hearbeat_interval round(:timer.seconds(Rihanna.Producer.grace_time_seconds()) / 2)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  def init(state) do
    start_heartbeat()
    {:ok, state}
  end

  def handle_call(job, _from, state) do
    %{mfa: {mod, fun, args}} = job

    task =
      Task.Supervisor.async_nolink(Rihanna.JobSupervisor, fn ->
        result = apply(mod, fun, args)
        success(job.id)
        result
      end)

    state = Map.put(state, task.ref, job)

    {:reply, :ok, state}
  end

  def handle_info({ref, _result}, state) do
    # Job completed successfully

    Process.demonitor(ref, [:flush])
    {_job, state} = Map.pop(state, ref)

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Job failed

    {job, state} = Map.pop(state, ref)
    failure(job.id, reason)

    {:noreply, state}
  end

  def handle_info(:heartbeat, state) do
    job_ids =
      state
      |> Map.values()
      |> Enum.map(fn %{id: id} -> id end)

    %{
      alive: alive,
      gone: gone
    } = heartbeat(job_ids)

    if Enum.any?(gone) do
      # TODO: What should we do here? Terminate the jobs?
      Logger.warn("Jobs were not found: #{inspect(gone)}")
    end

    {:noreply, state}
  end

  defp heartbeat([]), do: :noop

  defp heartbeat(job_ids) do
    Logger.debug("HEARTBEAT #{length(job_ids)} jobs are running")

    now = DateTime.utc_now()

    Rihanna.Job.mark_heartbeat(job_ids, now)
  end

  defp success(job_id) do
    Rihanna.Job.mark_successful(job_id)
  end

  defp failure(job_id, reason) do
    now = DateTime.utc_now()
    fail_reason = Exception.format_exit(reason)

    Rihanna.Job.mark_failed(job_id, now, fail_reason)
  end

  defp start_heartbeat() do
    {:ok, _ref} = :timer.send_interval(@hearbeat_interval, :heartbeat)
  end
end
