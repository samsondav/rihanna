defmodule Sombrero.Repo.Migrations.CreateJobs do
  use Ecto.Migration

  def change do
    create table(:jobs) do
      add :mfa, :bytea
      add :enqueued_at, :utc_datetime, null: false
      add :updated_at, :utc_datetime, null: false
      add :state, :string, null: false, default: "ready_to_run"
      add :expires_at, :utc_datetime
    end
  end
end
