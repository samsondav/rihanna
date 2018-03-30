defmodule Rihanna.JobTest do
  use ExUnit.Case, async: false
  import Rihanna.Job
  import TestHelper

  setup_all [:create_jobs_table]

  setup %{pg: pg} do
    Postgrex.query!(pg, "DELETE FROM rihanna_jobs;", [])
    job = insert_job(pg, :ready_to_run)
    {:ok, %{job: job}}
  end

  describe "retry_failed/1 when job has failed" do
    setup %{pg: pg} do
      failed_job = insert_job(pg, :failed)

      %{failed_job: failed_job}
    end

    test "returns {:ok, retried}", %{failed_job: failed_job} do
      assert {:ok, :retried} = retry_failed(failed_job.id)
    end

    test "nullifies failed_at and fail_reason", %{pg: pg, failed_job: failed_job} do
      retry_failed(failed_job.id)

      updated_job = get_job_by_id(pg, failed_job.id)

      assert updated_job.failed_at |> is_nil
      assert updated_job.fail_reason |> is_nil
    end

    test "resets enqueued_at", %{pg: pg, failed_job: failed_job} do
      assert {:ok, :retried} = retry_failed(pg, failed_job.id)

      updated_job = get_job_by_id(pg, failed_job.id)

      assert DateTime.compare(failed_job.enqueued_at, updated_job.enqueued_at) == :lt
    end
  end

  describe "retry_failed/1 when job has not failed" do
    test "returns {:error, :job_not_found}", %{pg: pg, job: job} do
      assert {:error, :job_not_found} = retry_failed(pg, job.id)
    end

    test "does not change job", %{pg: pg, job: job} do
      retry_failed(job.id)

      updated_job = get_job_by_id(pg, job.id)

      assert updated_job == job
    end
  end

  describe "lock/1 when job is ready to run" do
    setup %{pg: pg} do
      # Reset the locks before each test
      %{rows: [[:void]]} = Postgrex.query!(pg, "SELECT pg_advisory_unlock_all()", [])

      {:ok, pg2} = Postgrex.start_link(Application.fetch_env!(:rihanna, :postgrex))

      {:ok, %{pg2: pg2}}
    end

    test "returns job", %{job: %{id: id}, pg: pg} do
      assert %Rihanna.Job{id: ^id} = lock(pg)
    end

    test "takes advisory lock on first available job", %{job: %{id: id}, pg: pg, pg2: pg2} do
      assert %Rihanna.Job{id: ^id} = lock(pg)

      assert %{rows: [[false]]} = Postgrex.query!(pg2, "SELECT pg_try_advisory_lock($1)", [id])
    end

    test "does not lock job if advisory lock is already taken", %{job: %{id: id}, pg: pg, pg2: pg2} do
      assert %{rows: [[true]]} = Postgrex.query!(pg2, "SELECT pg_try_advisory_lock($1)", [id])

      assert lock(pg) |> is_nil
    end
  end

  describe "lock/2" do
    test "locks multiple jobs" do
    end

    test "skips jobs that are locked by another session" do
    end

    test "skips jobs that are already locked by this session" do
    end
  end

  describe "mark_successful" do
  end

  describe "mark_failed/3" do
    test "sets failed_at and reason", %{pg: pg} do
      job = insert_job(pg, :ready_to_run)
      %{rows: [[true]]} = Postgrex.query!(pg, "SELECT pg_try_advisory_lock($1)", [job.id])

      now = DateTime.utc_now()
      reason = "It went kaboom!"

      mark_failed(pg, job.id, now, reason)

      updated_job = get_job_by_id(pg, job.id)

      assert updated_job.failed_at == now
      assert updated_job.fail_reason == "It went kaboom!"
    end
  end
end
