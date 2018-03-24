defmodule Rihanna.JobManagerTest do
  use ExUnit.Case, async: false
  import TestHelper
  alias Rihanna.JobManager

  setup_all :create_jobs_table

  describe "handle_call/3" do
    setup do
      {:ok, %{js: Task.Supervisor.start_link(name: Rihanna.JobSupervisor)}}
    end

    test "adds job to state with ref", %{pg: pg} do
      job = insert_job(pg, :ready_to_run)

      assert {:reply, :ok, state} = JobManager.handle_call(job, self(), %{})

      assert map_size(state) == 1
      assert is_reference(hd(Map.keys(state)))
      assert hd(Map.values(state)) == job
    end

    test "runs the job in Rihanna.JobSupervisor" do
      {:ok, job} = Rihanna.Job.enqueue({Process, :send, [self(), "umbrella-ella-ella", []]})

      JobManager.handle_call(job, self(), %{})

      assert_receive "umbrella-ella-ella"
    end
  end

  describe "handle_info(:heartbeat, state)" do
    test "updates in progress jobs with latest heartbeat", %{pg: pg} do
      job = insert_job(pg, :in_progress)
      state = %{make_ref() => job}

      assert {:noreply, _state} = JobManager.handle_info(:heartbeat, state)

      updated_job = get_job_by_id(job.id)
      assert DateTime.compare(updated_job.heartbeat_at, job.heartbeat_at) == :gt
    end
  end
end
