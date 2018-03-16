defmodule Hyper.Job do
  use Ecto.Schema
  require Ecto.Query, as: Query

  @states ~w(
    ready_to_run
    in_progress
  )

  @grace_time_seconds 30

  schema "jobs" do
    field(:mfa, Hyper.ETF)
    field(:state, :string)
    field(:expires_at, :utc_datetime)

    timestamps(inserted_at: :enqueued_at)
  end

  def validate(changeset) do
    # TODO: write me
  end

  def expires_at(now) do
    now
    |> DateTime.to_unix()
    |> Kernel.+(@grace_time_seconds)
    |> DateTime.from_unix!()
  end
end
