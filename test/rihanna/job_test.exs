defmodule Rihanna.JobTest do
  use ExUnit.Case, async: false
  doctest Rihanna

  import Rihanna.Job
  import TestHelper

  setup_all [:create_jobs_table]

  @mfa {IO, :puts, ["Desperado, sittin' in an old Monte Carlo"]}

  describe "retry_failed/1 when job is in 'failed' state" do
    setup %{pg: pg} do
      result = Postgrex.query!(pg, """
      INSERT INTO "rihanna_jobs" (
        mfa,
        enqueued_at,
        updated_at,
        state,
        failed_at,
        fail_reason
      )
      VALUES ($1, '2018-01-01', '2018-01-01', 'failed', '2018-01-01', 'Kaboom!')
      RETURNING *
      """, [:erlang.term_to_binary(@mfa)])
      [job] = Rihanna.Job.from_sql(result.rows)

      {:ok, %{job: job}}
    end

    test "returns {:ok, retried}", %{job: job} do
      assert {:ok, :retried} = retry_failed(job.id)
    end

    test "sets job state to 'ready to run'", %{job: job} do
      retry_failed(job.id)

      updated_job = get_job_by_id(job.id)

      assert updated_job.state == "ready_to_run"
    end

    test "sets updated_at", %{job: job} do
      retry_failed(job.id)

      updated_job = get_job_by_id(job.id)

      assert DateTime.compare(job.updated_at, updated_job.updated_at) == :lt
    end

    test "sets enqueued_at", %{job: job} do
      retry_failed(job.id)

      updated_job = get_job_by_id(job.id)

      assert DateTime.compare(job.enqueued_at, updated_job.enqueued_at) == :lt
    end
  end

  describe "retry_failed/1 when job is not in 'failed' state" do
  end
end
