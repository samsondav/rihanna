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
        id: Rihanna.Postgrex,
        start: {Postgrex, :start_link, [Keyword.put(db, :name, Rihanna.Postgrex)]}
      },
      # %{
      #   id: Rihanna.Postgrex.Notifications,
      #   start:
      #     {Postgrex.Notifications, :start_link,
      #      [Keyword.put(db, :name, Rihanna.Postgrex.Notifications)]}
      # },
      {Task.Supervisor, name: Rihanna.JobSupervisor},
      # {Rihanna.JobManager, name: Rihanna.JobManager},
      # Rihanna.Producer
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
