defmodule Hyper.Worker do
  @module """
  Executes a single job.
  """

  require Ecto.Query, as: Query

  @doc """
  Start a worker process to execute the job.
  If it dies, don't attempt to save it - let the task expire in the DB and have
  the manager reschedule it.
  """
  def start(job = %{mfa: {mod, fun, args}}) do
    # Hyper.WorkerHeartbeat.start_link()
    IO.puts "spawning job task in pid #{inspect(self)}"
    Task.start(fn ->
      IO.puts "running job in pid #{inspect(self)}"
      apply(mod, fun, args)
      completed(job)
    end)
  end

  defp completed(job) do
    NestDB.Repo.delete_all(
      Query.from(
        j in Hyper.Job,
        where: j.id == ^job.id
      )
    )
  end
end
