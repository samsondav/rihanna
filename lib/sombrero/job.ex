defmodule Sombrero.Job do
  use Ecto.Schema
  require Ecto.Query, as: Query

  @states ~w(
    ready_to_run
    in_progress
    failed
  )

  @grace_time_seconds 30

  schema "jobs" do
    field(:mfa, Sombrero.ETF)
    field(:state, :string)
    field(:expires_at, :utc_datetime)

    timestamps(inserted_at: :enqueued_at)
  end

  def validate(_changeset) do
    # TODO: write me
  end

  def retry_failed(job_id) when is_binary(job_id) or is_integer(job_id) do
    now = DateTime.utc_now()
    result = Sombrero.Repo.update_all(
      Query.from(
        j in Sombrero.Job,
        where: j.state == "failed",
        where: j.id == ^job_id
      ),
      set: [
        state: "ready_to_run",
        expires_at: expires_at(now),
        updated_at: now,
        enqueued_at: now
      ]
    )

    case result do
      {0, _} ->
        {:error, :job_not_found}
      {1, [_job]} ->
        {:ok, :retried}
    end
  end

  def expires_at(now) do
    now
    |> DateTime.to_unix()
    |> Kernel.+(@grace_time_seconds)
    |> DateTime.from_unix!()
  end
end
