defmodule Rihanna.Supervisor do
  use Supervisor

  @moduledoc """
  TODO: Write some documentation
  """

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    children = [
      worker(Postgrex.Notifications, [Rihanna.Repo.config() ++ [name: Rihanna.PGNotifier]]),
      Rihanna.Repo,
      {Task.Supervisor, name: Rihanna.JobSupervisor},
      {Rihanna.JobManager, [name: Rihanna.JobManager]},
      Rihanna.Producer
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
