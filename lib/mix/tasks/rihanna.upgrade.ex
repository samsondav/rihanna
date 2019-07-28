defmodule Mix.Tasks.Rihanna.Upgrade do
  use Mix.Task

  @shortdoc "Upgrade an existing Rihanna database"
  def run(_) do
    {:ok, _started} = Application.ensure_all_started(:postgrex)

    db = Application.get_env(:rihanna, :postgrex)
    {:ok, pg} = Postgrex.start_link(db)

    for stmt <- Rihanna.Migration.statements() do
      with {:error, error} <- Postgrex.query(pg, stmt, []) do
        Mix.raise("#{error.postgres.code}: #{error.postgres.message}")
      end
    end

    Mix.shell().info("Upgraded database #{db[:database]}")
  end
end
