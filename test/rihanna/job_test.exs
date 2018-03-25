defmodule Rihanna.JobTest do
  use ExUnit.Case, async: false
  import Rihanna.Job
  import TestHelper

  setup_all [:create_jobs_table]

  describe "retry_failed/1 when job is in 'failed' state" do
    setup %{pg: pg} do
      job = insert_job(pg, :failed)
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

  describe "retry_failed/1 when job is not in 'ready_to_run' state" do
    setup %{pg: pg} do
      job = insert_job(pg, :ready_to_run)

      {:ok, %{job: job}}
    end

    test "returns {:error, :job_not_found}", %{job: job} do
      assert {:error, :job_not_found} = retry_failed(job.id)
    end

    test "does not change job", %{job: job} do
      retry_failed(job.id)

      updated_job = get_job_by_id(job.id)

      assert updated_job == job
    end
  end

  describe "lock_for_running/1 when job is in 'ready_to_run' state" do
    setup %{pg: pg} do
      job = insert_job(pg, :ready_to_run)

      {:ok, %{job: job}}
    end

    test "returns job", %{job: %{id: id}} do
      assert {:ok, %Rihanna.Job{id: ^id}} = lock_for_running(id)
    end

    test "sets job state to 'in_progress'", %{job: %{id: id}} do
      {:ok, _} = lock_for_running(id)

      updated_job = get_job_by_id(id)

      assert updated_job.state == "in_progress"
    end

    test "sets heartbeat_at to current time", %{job: job = %{id: id}} do
      {:ok, _} = lock_for_running(id)

      updated_job = get_job_by_id(id)

      refute is_nil(updated_job.heartbeat_at)
      assert DateTime.compare(job.updated_at, updated_job.heartbeat_at) == :lt
    end

    test "sets updated_at to current_time", %{job: job = %{id: id}} do
      {:ok, _} = lock_for_running(id)

      updated_job = get_job_by_id(id)

      assert DateTime.compare(job.updated_at, updated_job.updated_at) == :lt
    end
  end

  describe "lock_for_running/1 when job is in 'in_progress' state" do
    setup %{pg: pg} do
      job = insert_job(pg, :in_progress)

      {:ok, %{job: job}}
    end

    test "returns {:error, :missed_lock}", %{job: %{id: id}} do
      assert lock_for_running(id) == {:error, :missed_lock}
    end
  end

  describe "lock_for_running/1 when job is in 'failed' state" do
    setup %{pg: pg} do
      job = insert_job(pg, :failed)

      {:ok, %{job: job}}
    end

    test "returns {:error, :missed_lock}", %{job: %{id: id}} do
      assert lock_for_running(id) == {:error, :missed_lock}
    end
  end

  describe "ready_to_run_ids/0" do
    setup %{pg: pg} do
      Postgrex.query!(
        pg,
        """
        DELETE FROM rihanna_jobs;
        """,
        []
      )

      ready_to_run_jobs = for _ <- 1..3, do: insert_job(pg, :ready_to_run)
      insert_job(pg, :in_progress)
      insert_job(pg, :failed)

      {:ok, %{ready_to_run_jobs: ready_to_run_jobs}}
    end

    test "returns ids of ready to run jobs", %{ready_to_run_jobs: ready_to_run_jobs} do
      expected_ids = for %{id: id} <- ready_to_run_jobs, do: id
      assert ready_to_run_ids() == expected_ids
    end
  end

  describe "mark_heartbeat/2" do
    test "updates heartbeat and updated_at of 'in_progress' jobs", %{pg: pg} do
      job_ids = for _ <- 1..3, do: insert_job(pg, :in_progress).id

      now = DateTime.utc_now()

      assert %{
               alive: job_ids,
               gone: []
             } = mark_heartbeat(job_ids, now)

      Enum.each(job_ids, fn id ->
        job = get_job_by_id(id)
        assert job.heartbeat_at == now
        assert job.updated_at == now
      end)
    end

    test "returns job in 'ready_to_run' state as removed", %{pg: pg} do
      job_ids = [insert_job(pg, :ready_to_run).id]

      assert %{
               alive: [],
               gone: ^job_ids
             } = mark_heartbeat(job_ids, DateTime.utc_now())
    end

    test "returns job in 'failed' state as removed", %{pg: pg} do
      job_ids = [insert_job(pg, :failed).id]

      assert %{
               alive: [],
               gone: ^job_ids
             } = mark_heartbeat(job_ids, DateTime.utc_now())
    end

    test "returns deleted job as removed" do
      job_ids = [-1]

      assert %{
               alive: [],
               gone: [-1]
             } = mark_heartbeat(job_ids, DateTime.utc_now())
    end
  end

  describe "mark_successful" do
  end

  describe "mark_failed/3" do
    test "moves job into failed state and sets failed_at and reason", %{pg: pg} do
      job = insert_job(pg, :in_progress)
      now = DateTime.utc_now()
      reason = "It went kaboom!"

      mark_failed(job.id, now, reason)

      updated_job = get_job_by_id(job.id)

      assert updated_job.state == "failed"
      assert updated_job.failed_at == now
      assert updated_job.updated_at == now
      assert updated_job.heartbeat_at == nil
      assert updated_job.fail_reason == "It went kaboom!"
    end
  end
end
