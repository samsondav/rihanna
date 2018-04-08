defmodule Rihanna.JobDispatcherTest do
  use ExUnit.Case, async: false
  import TestHelper
  alias Rihanna.JobDispatcher

  setup_all :create_jobs_table

  def initial_state(pg) do
    %{working: %{}, pg: pg}
  end

  defmodule BehaviourMock do
    @behaviour Rihanna.Job

    def perform([pid, msg]) do
      Process.send(pid, {msg, self()}, [])
      :ok
    end
  end

  defmodule MFAMock do
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

      assert_unordered_list_equality(Map.keys(state), [:working, :pg])
      assert state.pg == pg

      working = state.working

      assert map_size(working) == 1
      assert is_reference(hd(Map.keys(working)))
      assert hd(Map.values(working)) == job
    end

    test "runs mfa-style job in Rihanna.JobSupervisor", %{pg: pg} do
      {:ok, _job} = Rihanna.Job.enqueue({MFAMock, :fun, [self(), "umbrella-ella-ella"]})

      JobDispatcher.handle_info(:poll, initial_state(pg))

      assert_receive {"umbrella-ella-ella", worker_pid}
      assert worker_pid != self()
    end

    test "runs behaviour-style job in Rihanna.JobSupervisor", %{pg: pg} do
      {:ok, _job} = Rihanna.Job.enqueue({BehaviourMock, [self(), "Bitch better have my money"]})

      JobDispatcher.handle_info(:poll, initial_state(pg))

      assert_receive {"Bitch better have my money", worker_pid}
      assert worker_pid != self()
    end
  end

  describe "handle_info(:poll, state) with multiple jobs" do
    setup do
      Application.put_env(:rihanna, :dispatcher_max_concurrency, 2)
      :ok
    end

    test "executes up to dispatcher_max_concurrency() jobs", %{pg: pg} do
      _jobs =
        Enum.map(1..3, fn n -> Rihanna.Job.enqueue({MFAMock, :fun, [self(), "job-#{n}"]}) end)

      JobDispatcher.handle_info(:poll, initial_state(pg))

      assert_receive {"job-1", _}
      assert_receive {"job-2", _}
      refute_receive {"job-3", _}
    end
  end

  # TODO: Two more handle_info tests
  describe "handle_info/2 with successful job" do
    test "demonitors process" do
    end

    test "marks job as successful" do
    end

    test "removes task from state"
  end

  describe "handle_info/2 with failed job" do
    test "demonitors process" do
    end

    test "marks job as failed" do
    end

    test "removes task from state" do
    end
  end
end
