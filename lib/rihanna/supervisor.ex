defmodule Rihanna.Supervisor do
  use Supervisor

  @moduledoc """
  TODO: Write some documentation
  """

  def start_link(config, opts \\ []) do
    {db, config} = Keyword.pop_first(config, :postgrex, [])
    case db do
      [] ->
        raise """
        Could not start Rihanna - database configuration was missing. Did you forget to pass postgres configuration into Rihanna.Supervisor?

        For example:

        children = [
          {Rihanna.Supervisor, [postgrex: %{username: "postgres", password: "postgres", database: "rihanna_db", hostname: "localhost", port: 5432}]}
        ]
        """
      db ->
        db = Keyword.take(db, [:username, :password, :database, :hostname, :port])
        Supervisor.start_link(__MODULE__, {db, config}, opts)
    end
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
