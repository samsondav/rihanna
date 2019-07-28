defmodule Mix.Tasks.Rihanna.Migrate do
  use Mix.Task

  @shortdoc "Runs the necessary Rihanna migrations"
  def run(_) do
    {:ok, _started} = Application.ensure_all_started(:postgrex)

    db = Application.get_env(:rihanna, :postgrex)
    {:ok, pg} = Postgrex.start_link(db)

    for stmt <- Rihanna.Migration.statements() do
      with {:error, error} <- Postgrex.query(pg, stmt, []) do
        Mix.raise("#{error.postgres.code}: #{error.postgres.message}")
      end
    end

    Mix.shell().info("Migrated database #{db[:database]}")
  end
end
