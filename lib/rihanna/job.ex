defmodule Rihanna.Job do
  require Logger

  @moduledoc """
  Valid states are:
    ready_to_run
    in_progress
    failed

  """

  @fields [
    :id,
    :mfa,
    :enqueued_at,
    :updated_at,
    :state,
    :heartbeat_at,
    :failed_at,
    :fail_reason
  ]

  defstruct @fields

  def start(job) do
    GenServer.call(Rihanna.JobManager, job)
  end

  def enqueue(mfa) do
    serialized_mfa = :erlang.term_to_binary(mfa)
    now = DateTime.utc_now()

    %{rows: [job]} =
      query!(
        """
          INSERT INTO "#{table()}" (mfa, enqueued_at, updated_at, state)
          VALUES ($1, $2, $2, 'ready_to_run')
          RETURNING #{sql_fields()}
        """,
        [serialized_mfa, now]
      )

    {:ok, from_sql(job)}
  end

  def from_sql(rows = [row | _]) when is_list(rows) and is_list(row) do
    for row <- rows, do: from_sql(row)
  end

  def from_sql([
        id,
        serialized_mfa,
        enqueued_at,
        updated_at,
        state,
        heartbeat_at,
        failed_at,
        fail_reason
      ]) do
    %__MODULE__{
      id: id,
      mfa: :erlang.binary_to_term(serialized_mfa),
      enqueued_at: enqueued_at,
      updated_at: updated_at,
      state: state,
      heartbeat_at: heartbeat_at,
      failed_at: failed_at,
      fail_reason: fail_reason
    }
  end

  def retry_failed(job_id) when is_binary(job_id) or is_integer(job_id) do
    now = DateTime.utc_now()

    result =
      query!(
        """
          UPDATE "#{table()}"
          SET
            state = 'ready_to_run',
            updated_at = $1,
            enqueued_at = $1
          WHERE
            state = 'failed' AND id = $2
        """,
        [now, job_id]
      )

    case result.num_rows do
      0 ->
        {:error, :job_not_found}

      1 ->
        {:ok, :retried}
    end
  end

  def lock_for_running(job_id) when is_binary(job_id) or is_integer(job_id) do
    now = DateTime.utc_now()

    result =
      query!(
        """
        UPDATE "#{table()}"
        SET
          state = 'in_progress',
          heartbeat_at = $1,
          updated_at = $1
        WHERE
          id = $2 AND state = 'ready_to_run'
        RETURNING
          #{sql_fields()}
        """,
        [now, job_id]
      )

    case result.num_rows do
      1 ->
        [job] = result.rows |> from_sql()
        Logger.debug("Got lock for job #{job.id} in pid #{inspect(self())}")
        {:ok, job}

      0 ->
        Logger.debug("Missed lock for job #{job_id} in pid #{inspect(self())}")
        {:error, :missed_lock}
    end
  end

  def ready_to_run_ids() do
    query!(
      """
      SELECT id FROM "#{table()}"
      WHERE state = 'ready_to_run'
      """,
      []
    )
    |> Map.fetch!(:rows)
    |> Enum.map(fn [id] when is_integer(id) -> id end)
  end

  def mark_heartbeat(job_ids, now) do
    {query_params, job_ids} =
      job_ids
      |> Enum.with_index(2)
      |> Enum.map(fn {job_id, idx} ->
        {"$#{idx}", job_id}
      end)
      |> Enum.unzip()

    %{rows: rows} =
      query!(
        """
          UPDATE "#{table()}"
          SET
            heartbeat_at = $1,
            updated_at = $1
          WHERE
            id IN (#{Enum.join(query_params, ", ")})
              AND
            state = 'in_progress'
          RETURNING id
        """,
        [now | job_ids]
      )

    alive_job_ids = for [id] <- rows, do: id

    %{
      alive: alive_job_ids,
      gone: job_ids -- alive_job_ids
    }
  end

  # MARK: test from here down

  def mark_successful(job_id) do
    query!(
      """
        DELETE FROM "#{table()}"
        WHERE id = $1
      """,
      [job_id]
    )
  end

  def mark_failed(job_id, now, fail_reason) do
    query!(
      """
        UPDATE "#{table()}"
        SET
          state = 'failed',
          failed_at = $1,
          fail_reason = $2,
          heartbeat_at = NULL,
          updated_at = $1
        WHERE
          id = $3
      """,
      [now, fail_reason, job_id]
    )
  end

  def sweep_for_expired(now, assume_dead) do
    query!(
      """
      UPDATE "#{table()}"
      SET
        state = "failed",
        heartbeat_at = NULL,
        failed_at = $1,
        fail_reason = 'Unknown: worker went AWOL'
      WHERE
        state = 'in_progress' AND j.heartbeat_at <= $2
      """,
      [now, assume_dead]
    )
  end

  defp query!(query, params) do
    Postgrex.query!(Rihanna.Postgrex, query, params)
  end

  defp table() do
    Rihanna.Config.jobs_table_name()
  end

  defp sql_fields() do
    @fields
    |> Enum.map(&to_string/1)
    |> Enum.join(", ")
  end
end
