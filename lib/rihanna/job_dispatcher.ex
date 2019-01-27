defmodule Rihanna.JobDispatcher do
  use GenServer

  @task_supervisor Rihanna.TaskSupervisor

  @moduledoc false

  def start_link(config, opts) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  @doc false
  def init(config) do
    db = Keyword.get(config, :db)
    startup_delay = Keyword.get(config, :startup_delay, Rihanna.Config.startup_delay())

    # NOTE: These are linked because it is important that the pg session is also
    # killed if the JobDispatcher dies since otherwise we may leave dangling
    # locks in the zombie pg process
    {:ok, pg} = Postgrex.start_link(db)

    state = %{working: %{}, pg: pg}

    # Use a startup delay to avoid killing the supervisor if we can't connect
    # to the database for some reason.
    Process.send_after(self(), :initialise, startup_delay)
    {:ok, state}
  end

  def handle_info(:initialise, state = %{pg: pg}) do
    check_database!(pg)
    Process.send(self(), :poll, [])
    {:noreply, state}
  end

  def handle_info(:poll, state = %{working: working, pg: pg}) do
    jobs = lock_jobs_for_execution(pg, working)

    working =
      for job <- jobs, into: working do
        task = spawn_supervised_task(job)
        {task.ref, job}
      end

    state = Map.put(state, :working, working)

    Process.send_after(self(), :poll, poll_interval())

    {:noreply, state}
  end

  def handle_info({ref, result}, state = %{pg: pg, working: working}) do
    # Flush guarantees that any DOWN messages will be received before
    # demonitoring. This is probably unnecessary but it can't hurt to be sure.
    Process.demonitor(ref, [:flush])

    {job, working} = Map.pop(working, ref)

    case result do
      {:error, _} ->
        job_failure(job, result, pg)

      :error ->
        job_failure(job, result, pg)

      _ ->
        Rihanna.Job.mark_successful(pg, job.id)
    end

    state = Map.put(state, :working, working)

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state = %{pg: pg, working: working}) do
    {job, working} = Map.pop(working, ref)
    job_raised(job, reason, pg)
    {:noreply, Map.put(state, :working, working)}
  end

  defp job_raised(%{id: id, term: {job_module, arg}}, reason, pg) do
    # NOTE: Do we need to demonitor here?
    Rihanna.Job.mark_failed(pg, id, DateTime.utc_now(), Exception.format_exit(reason))
    Rihanna.Job.after_error(job_module, reason, arg)
  end

  defp job_raised(job, reason, pg) do
    # NOTE: Do we need to demonitor here?
    Rihanna.Job.mark_failed(pg, job.id, DateTime.utc_now(), Exception.format_exit(reason))
  end

  defp job_failure(%{id: id, term: {job_module, arg}}, reason, pg) do
    # NOTE: Do we need to demonitor here?
    Rihanna.Job.mark_failed(
      pg,
      id,
      DateTime.utc_now(),
      "Job Failed\n#{inspect(reason, limit: :infinity)}"
    )

    Rihanna.Job.after_error(job_module, reason, arg)
  end

  defp job_failure(job, reason, pg) do
    # NOTE: Do we need to demonitor here?
    Rihanna.Job.mark_failed(pg, job.id, DateTime.utc_now(), Exception.format_exit(reason))
  end

  defp check_database!(pg) do
    Rihanna.Migration.check_table!(pg)
    Rihanna.Migration.check_upgrade_not_required!(pg)
  end

  defp lock_jobs_for_execution(pg, working) do
    # Fill the pipeline with as much work as we can get
    available_concurrency = max_concurrency() - Enum.count(working)

    currently_locked_job_ids = for %{id: id} <- Map.values(working), do: id

    Rihanna.Job.lock(pg, available_concurrency, currently_locked_job_ids)
  end

  defp spawn_supervised_task(job) do
    Task.Supervisor.async_nolink(@task_supervisor, fn ->
      Rihanna.Logger.log(:debug, fn -> "[Rihanna] Starting job #{job.id}" end)

      result =
        case job.term do
          {mod, fun, args} ->
            # It's a simple MFA
            if Rihanna.Config.behaviour_only?() do
              raise "[Rihanna] Cannot execute MFA job because Rihanna was configured with the `behaviour_only` config option set to true."
            else
              apply(mod, fun, args)
            end

          {mod, arg} ->
            # Assume that mod conforms to Rihanna.Job behaviour
            # TODO: Mark as failed if job returns error
            # TODO: Add `on_completion` hook that passes in result of job
            apply(mod, :perform, [arg])
        end

      Rihanna.Logger.log(:debug, fn -> "[Rihanna] Finished job #{job.id}" end)
      result
    end)
  end

  defp max_concurrency() do
    Rihanna.Config.dispatcher_max_concurrency()
  end

  defp poll_interval() do
    base_poll_interval = Rihanna.Config.dispatcher_poll_interval()
    jitter_fraction = 0.2 * :rand.uniform() - 0.1
    jitter = base_poll_interval * jitter_fraction

    (base_poll_interval + jitter) |> round
  end
end
