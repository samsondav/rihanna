defmodule Mix.Tasks.Rihanna.Drop do
  use Mix.Task

  @maintenance_database "postgres"

  @shortdoc "Drop the Rihanna database"
  def run(_) do
    {:ok, _started} = Application.ensure_all_started(:postgrex)

    db = Application.get_env(:rihanna, :postgrex)

    {:ok, pg} =
      db
      |> Keyword.put(:database, @maintenance_database)
      |> Postgrex.start_link()

    case Postgrex.query(pg, "DROP DATABASE #{db[:database]};", []) do
      {:ok, _} ->
        Mix.shell().info("Dropped database #{db[:database]}")

      {:error, error} ->
        Mix.raise("#{error.postgres.code}: #{error.postgres.message}")
    end
  end
end
