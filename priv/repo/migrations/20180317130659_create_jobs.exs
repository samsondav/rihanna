defmodule Rihanna.Repo.Migrations.CreateJobs do
  use Ecto.Migration
  require Rihanna.Migration

  @table_name Rihanna.Config.jobs_table_name()

  def change do
    Rihanna.Migration.change(@table_name)
  end
end
