defmodule Sombrero.Repo.Migrations.AddFailedAtAndFailReason do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :failed_at, :utc_datetime
      add :fail_reason, :text
    end
  end
end
