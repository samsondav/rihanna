defmodule Sombrero.Worker do
  @module """
  Executes a single job.
  """

  require Logger
  require Ecto.Query, as: Query

  @doc """
  Start a worker process to execute the job.
  If it dies, don't attempt to save it - let the task expire in the DB and have
  the manager reschedule it.
  """
  def start(job = %{mfa: {mod, fun, args}}) do
    Logger.debug("Spawning worker task in pid #{inspect(self)}")

    Task.start(fn ->
      Process.flag(:trap_exit, true)

      job_pid = spawn_link(mod, fun, args)
      Logger.debug("Running job in pid #{inspect(self)}")
      {:ok, heartbeat} = start_heartbeat(job)
      Logger.debug("Hearbeat is running in #{inspect(heartbeat)}")
      receive do
        {:EXIT, ^job_pid, :normal} ->
          Logger.debug("Process #{inspect job_pid} exited normally")
          Logger.debug("Finished job")
          success(job.id)
        {:EXIT, ^job_pid, reason} ->
          Logger.debug("Process #{inspect job_pid} exited abnormally with reason #{inspect(reason)}")
          failure(job.id, reason)
      end
      Logger.debug("Stopping heartbeat in #{inspect heartbeat}")
      Process.exit(heartbeat, :kill)
      Logger.debug("Worker task done")
    end)
  end

  defp start_heartbeat(job) do
    Supervisor.start_link([
      {Sombrero.WorkerHeartbeat, job}
    ], strategy: :one_for_one)
  end

  defp success(job_id) do
    Sombrero.Repo.delete_all(
      Query.from(
        j in Sombrero.Job,
        where: j.id == ^job_id
      )
    )
  end

  defp failure(job_id, reason) do
    now = DateTime.utc_now()
    {1, nil} = Sombrero.Repo.update_all(
      Query.from(
        j in Sombrero.Job,
        where: j.id == ^job_id
      ),
      [
        set: [
          state: "failed",
          failed_at: now,
          fail_reason: Exception.format_exit(reason),
          expires_at: nil,
          updated_at: now
        ]
      ]
    )
  end
end
