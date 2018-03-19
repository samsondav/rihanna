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
      # FIXME: heartbeat runs forever?
      {:ok, heartbeat} = Sombrero.WorkerHeartbeat.start_link(job)
      Logger.debug("Hearbeat is running in #{inspect(heartbeat)}")
      Logger.debug("Running job in pid #{inspect(self)}")

      # TODO: Can we trap failures and proactively mark the job as failed so we don't have to wait for the poll?
      apply(mod, fun, args)
      Logger.debug("Finished job")
      completed(job)
      Logger.debug("Worker task done")
    end)
  end

  defp completed(job) do
    Sombrero.Repo.delete_all(
      Query.from(
        j in Sombrero.Job,
        where: j.id == ^job.id
      )
    )
  end
end
