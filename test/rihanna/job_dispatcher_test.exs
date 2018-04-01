defmodule Rihanna.JobDispatcherTest do
  use ExUnit.Case, async: false
  import TestHelper
  alias Rihanna.JobDispatcher

  setup_all :create_jobs_table

  def initial_state(pg) do
    %{working: %{}, pg: pg}
  end

  defmodule TestRig do
    def fun(pid, msg) do
      Process.send(pid, {msg, self()}, [])
    end
  end

  setup %{pg: pg} do
    Postgrex.query!(pg, "DELETE FROM rihanna_jobs;", [])
    {:ok, %{js: Task.Supervisor.start_link(name: Rihanna.TaskSupervisor)}}
  end

  describe "handle_info(:poll, state) with one available job" do
    test "retrieves the job and puts it into the state", %{pg: pg} do
      job = insert_job(pg, :ready_to_run)

      assert {:noreply, state} = JobDispatcher.handle_info(:poll, initial_state(pg))

      assert_unordered_list_equality Map.keys(state), [:working, :pg]
      assert state.pg == pg

      working = state.working

      assert map_size(working) == 1
      assert is_reference(hd(Map.keys(working)))
      assert hd(Map.values(working)) == job
    end

    test "runs the job in Rihanna.JobSupervisor", %{pg: pg} do
      {:ok, _job} = Rihanna.Job.enqueue({TestRig, :fun, [self(), "umbrella-ella-ella"]})

      JobDispatcher.handle_info(:poll, initial_state(pg))

      assert_receive {"umbrella-ella-ella", worker_pid}
      assert worker_pid != self()
    end
  end

  describe "handle_info(:poll, state) with multiple jobs" do
    setup do
      Application.put_env(:rihanna, :dispatcher_max_concurrency, 2)
      :ok
    end

    test "executes up to dispatcher_max_concurrency() jobs", %{pg: pg} do
      _jobs = Enum.map(1..3, fn n -> Rihanna.Job.enqueue({TestRig, :fun, [self(), "job-#{n}"]}) end)

      JobDispatcher.handle_info(:poll, initial_state(pg))

      assert_receive {"job-1", _}
      assert_receive {"job-2", _}
      refute_receive {"job-3", _}
    end
  end
end
