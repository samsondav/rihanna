defmodule Rihanna.Supervisor do
  use Supervisor

  @moduledoc """
  TODO: Write some documentation
  """

  def start_link(config, opts \\ []) do
    {db, config} = Keyword.pop_first(config, :postgrex, [])
    Supervisor.start_link(__MODULE__, {db, config}, opts)
  end

  def init({db, _config}) do
    children = [
      %{
        id: Rihanna.Job.Postgrex,
        start: {Postgrex, :start_link, [Keyword.put(db, :name, Rihanna.Job.Postgrex)]}
      },
      {Task.Supervisor, name: Rihanna.TaskSupervisor},
      %{
        id: Rihanna.JobDispatcher,
        start: {Rihanna.JobDispatcher, :start_link, [[db: db], [name: Rihanna.JobDispatcher]]}
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
