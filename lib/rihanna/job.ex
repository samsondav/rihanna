defmodule Rihanna.Job do
  use Ecto.Schema
  require Ecto.Query, as: Query

  @moduledoc """
  Valid states are:
    ready_to_run
    in_progress
    failed

  """

  schema Rihanna.Config.jobs_table_name() do
    field(:mfa, Rihanna.ETF)
    field(:state, :string)
    field(:heartbeat_at, :utc_datetime)
    field(:failed_at, :utc_datetime)
    field(:fail_reason, :string)

    timestamps(inserted_at: :enqueued_at, type: :utc_datetime)
  end

  def start(job) do
    GenServer.call(Rihanna.JobManager, job)
  end

  def retry_failed(job_id) when is_binary(job_id) or is_integer(job_id) do
    now = DateTime.utc_now()

    result =
      Rihanna.Repo.update_all(
        Query.from(
          j in Rihanna.Job,
          where: j.state == "failed",
          where: j.id == ^job_id
        ),
        [
          set: [
            state: "ready_to_run",
            heartbeat_at: now,
            updated_at: now,
            enqueued_at: now
          ]
        ],
        returning: true
      )

    case result do
      {0, _} ->
        {:error, :job_not_found}

      {1, [_job]} ->
        {:ok, :retried}
    end
  end
end
