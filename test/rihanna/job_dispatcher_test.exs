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

  defp lock_held?(pg, id) do
    %{num_rows: num_rows} = Postgrex.query!(pg, """
      SELECT objid
      FROM pg_locks
      WHERE locktype = 'advisory'
      AND classid = $1
      AND pg_locks.pid = pg_backend_pid()
      AND pg_locks.objid = $2
    """, [Rihanna.Config.pg_advisory_lock_class_id(), id])

    case num_rows do
      0 ->
        false
      1 ->
        true
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
    setup do
      {:ok, dispatcher} = Rihanna.JobDispatcher.start_link([db: Application.fetch_env!(:rihanna, :postgrex)], [])
      {:ok, %{dispatcher: dispatcher}}
    end

    test "marks job as successful", %{pg: pg} do
      {:ok, %{id: id}} = Rihanna.Job.enqueue({MFAMock, :fun, [self(), "job-mark-successful"]})

      :timer.sleep(100)

      assert get_job_by_id(pg, id) == nil
      refute lock_held?(pg, id)
    end

    test "removes task from state", %{dispatcher: dispatcher} do
      Rihanna.Job.enqueue({MFAMock, :fun, [self(), "job-test-remove-task-from-state"]})

      assert_receive {"job-test-remove-task-from-state", _}
      :timer.sleep(100)

      state = :sys.get_state(dispatcher)

      refute Enum.any?(state.working)
      assert is_pid(state.pg)
    end
  end

  describe "handle_info/2 with failed job" do
    setup do
      {:ok, dispatcher} = Rihanna.JobDispatcher.start_link([db: Application.fetch_env!(:rihanna, :postgrex)], [])
      {:ok, %{dispatcher: dispatcher}}
    end

    test "marks job as failed", %{pg: pg} do
      {:ok, %{id: id}} = Rihanna.Job.enqueue({Nope, :broken, [:kaboom!]})

      :timer.sleep(100)

      job = get_job_by_id(pg, id)

      assert %DateTime{} = job.failed_at
      assert job.fail_reason == "an exception was raised:\n    ** (UndefinedFunctionError) function Nope.broken/1 is undefined (module Nope is not available)\n        Nope.broken(:kaboom!)\n        (elixir) lib/task/supervised.ex:88: Task.Supervised.do_apply/2\n        (elixir) lib/task/supervised.ex:38: Task.Supervised.reply/5\n        (stdlib) proc_lib.erl:247: :proc_lib.init_p_do_apply/3"
    end

    test "removes task from state", %{dispatcher: dispatcher} do
      Rihanna.Job.enqueue({Nope, :broken, [:kaboom!]})

      :timer.sleep(100)

      state = :sys.get_state(dispatcher)

      refute Enum.any?(state.working)
      assert is_pid(state.pg)
    end
  end
end
