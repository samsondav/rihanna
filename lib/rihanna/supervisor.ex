defmodule Rihanna.Supervisor do
  use Supervisor

  @moduledoc """
  TODO: Write some documentation
  """

  def start_link(opts) do
    {config, opts} = Keyword.pop(opts, :config)
    Supervisor.start_link(__MODULE__, config, opts)
  end

  def init(config) do
    children = [
      {Postgrex, Keyword.put(config, :name, Rihanna.Postgrex)},
      worker(Postgrex.Notifications, Keyword.put(config, :name, Rihanna.Postgrex)),
      {Task.Supervisor, name: Rihanna.JobSupervisor},
      {Rihanna.JobManager, [name: Rihanna.JobManager]},
      Rihanna.Producer
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

