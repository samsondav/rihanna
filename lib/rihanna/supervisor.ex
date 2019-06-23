defmodule Rihanna.Supervisor do
  use Supervisor

  @moduledoc """
  The main supervisor for Rihanna.

  Starts the Postgrex process necessary for enqueueing jobs, and also starts a
  dispatcher for processing them.

  ## Setup

  Add `Rihanna.Supervisor` to your supervision tree.

  By adding it to your supervision tree it will automatically start running jobs
  when your app boots.

  Rihanna requires a database configuration to be passed in under the `postgrex`
  key. This is passed through directly to Postgrex.

  If you are already using Ecto you can avoid duplicating your DB config by
  pulling this out of your existing Repo using `My.Repo.config()`.

  ```
  # NOTE: In Phoenix you would find this inside `lib/my_app/application.ex`
  children = [
    {Rihanna.Supervisor, [name: Rihanna.Supervisor, postgrex: My.Repo.config()]}
  ]
  ```
  """

  def start_link(config, opts \\ []) do
    case Keyword.pop_first(config, :postgrex) do
      {nil, _} ->
        raise """
        Could not start Rihanna - database configuration was missing. Did you forget to pass postgres configuration into Rihanna.Supervisor?

        For example:

        children = [
          {Rihanna.Supervisor, [postgrex: %{username: "postgres", password: "postgres", database: "rihanna_db", hostname: "localhost", port: 5432}]}
        ]
        """

      {db, config} ->
        db = Keyword.drop(db, [:pool, :pool_size])
        Supervisor.start_link(__MODULE__, Keyword.merge(config, [db: db]), opts)
    end
  end

  @doc false
  def init(config) do
    children =
      [
        producer_postgres_connection(Keyword.get(config, :db)),
        {Task.Supervisor, name: Rihanna.TaskSupervisor},
        %{
          id: Rihanna.JobDispatcher,
          start: {Rihanna.JobDispatcher, :start_link, [config, [name: Rihanna.JobDispatcher]]}
        }
      ]
      |> Enum.filter(& &1)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp producer_postgres_connection(db) do
    unless(Rihanna.Config.producer_postgres_connection_supplied?()) do
      %{
        id: Rihanna.Job.Postgrex,
        start: {Postgrex, :start_link, [Keyword.put(db, :name, Rihanna.Job.Postgrex)]}
      }
    end
  end
end
