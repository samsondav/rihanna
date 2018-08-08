defmodule Rihanna.JobDispatcherTest do
  use ExUnit.Case, async: false
  import TestHelper
  alias Rihanna.JobDispatcher

  alias Rihanna.Mocks.{
    LongJob,
    BehaviourMock,
    MFAMock,
    BadMFAMock,
    ErrorBehaviourMock,
    ErrorTupleBehaviourMock
  }

  setup_all :create_jobs_table

  def initial_state(pg) do
    %{working: %{}, pg: pg}
  end

  defp lock_held?(pg, id) do
    %{num_rows: num_rows} =
      Postgrex.query!(
        pg,
        """
          SELECT objid
          FROM pg_locks
          WHERE locktype = 'advisory'
          AND classid = $1
          AND pg_locks.pid = pg_backend_pid()
          AND pg_locks.objid = $2
        """,
        [Rihanna.Config.pg_advisory_lock_class_id(), id]
      )

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

  describe "linking processes" do
    setup do
      {:ok, dispatcher} =
        Rihanna.JobDispatcher.start_link([db: Application.fetch_env!(:rihanna, :postgrex)], [])

      {:ok, %{dispatcher: dispatcher}}
    end

    test "it will crash if it's Postgrex connection crashes as well", %{dispatcher: dispatcher} do
      Process.flag(:trap_exit, true)
      pg_session = :sys.get_state(dispatcher).pg

      Process.exit(pg_session, :kill)

      assert_receive {:EXIT, ^dispatcher, _}
    end
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

  describe "when behaviour_only: true" do
    setup do
      Application.put_env(:rihanna, :behaviour_only, true)

      on_exit(fn ->
        Application.put_env(:rihanna, :behaviour_only, false)
      end)

      :ok
    end

    test "does not run mfa-style job if behaviour_only config is set", %{pg: pg} do
      {:ok, _job} = Rihanna.Job.enqueue({MFAMock, :fun, [self(), "umbrella-ella-ella"]})

      JobDispatcher.handle_info(:poll, initial_state(pg))

      assert_receive {:DOWN, _ref, :process, _pid,
                      {%RuntimeError{
                         message:
                           "[Rihanna] Cannot execute MFA job because Rihanna was configured with the `behaviour_only` config option set to true."
                       }, _}}

      refute_receive {"umbrella-ella-ella", _}
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

    test "does not lock jobs already working", %{pg: pg} do
      [{:ok, job} | _] =
        Enum.map(1..3, fn n -> Rihanna.Job.enqueue({MFAMock, :fun, [self(), "job-#{n}"]}) end)

      JobDispatcher.handle_info(:poll, %{working: %{make_ref() => job}, pg: pg})

      refute_receive {"job-1", _}
      assert_receive {"job-2", _}
      refute_receive {"job-3", _}
    end
  end

  # TODO: Two more handle_info tests
  describe "handle_info/2 with successful job" do
    setup do
      {:ok, dispatcher} =
        Rihanna.JobDispatcher.start_link([db: Application.fetch_env!(:rihanna, :postgrex)], [])

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

  describe "handle_info/2 with job that returns error" do
    setup do
      {:ok, dispatcher} =
        Rihanna.JobDispatcher.start_link([db: Application.fetch_env!(:rihanna, :postgrex)], [])

      {:ok, %{dispatcher: dispatcher}}
    end

    test "marks job as failed when returns {:error, reason}", %{pg: pg} do
      ref = make_ref()
      {:ok, %{id: id}} = Rihanna.Job.enqueue({ErrorTupleBehaviourMock, [self(), ref]})
      :timer.sleep(100)
      %Rihanna.Job{fail_reason: reason} = get_job_by_id(pg, id)
      assert reason == "Job Failed\n{:error, \"failed for some reason\"}"
    end

    test "removes task from state when returns {:error, reason}", %{dispatcher: dispatcher} do
      ref = make_ref()
      Rihanna.Job.enqueue({ErrorTupleBehaviourMock, [self(), ref]})

      assert_receive {^ref, _}

      :timer.sleep(100)

      state = :sys.get_state(dispatcher)

      refute Enum.any?(state.working)
      assert is_pid(state.pg)
    end

    test "marks job as failed when returns :error", %{pg: pg} do
      ref = make_ref()
      {:ok, %{id: id}} = Rihanna.Job.enqueue({ErrorBehaviourMock, [self(), ref]})
      :timer.sleep(100)
      %Rihanna.Job{fail_reason: reason} = get_job_by_id(pg, id)
      assert reason == "Job Failed\n{:error, \"failed for some reason\"}"
    end

    test "removes task from state when returns :error", %{dispatcher: dispatcher} do
      ref = make_ref()
      Rihanna.Job.enqueue({ErrorBehaviourMock, [self(), ref]})

      assert_receive {^ref, _}

      :timer.sleep(100)

      state = :sys.get_state(dispatcher)

      refute Enum.any?(state.working)
      assert is_pid(state.pg)
    end
  end

  describe "handle_info/2 with missing module" do
    setup do
      {:ok, dispatcher} =
        Rihanna.JobDispatcher.start_link([db: Application.fetch_env!(:rihanna, :postgrex)], [])

      {:ok, %{dispatcher: dispatcher}}
    end

    test "marks job as failed", %{pg: pg} do
      {:ok, %{id: id}} = Rihanna.Job.enqueue({Nope, :broken, [:kaboom!]})

      :timer.sleep(100)

      job = get_job_by_id(pg, id)

      assert %DateTime{} = job.failed_at

      assert "an exception was raised:\n    ** (UndefinedFunctionError) function Nope.broken/1 is undefined (module Nope is not available)" <>
               _rest = job.fail_reason
    end

    test "removes task from state", %{dispatcher: dispatcher} do
      Rihanna.Job.enqueue({Nope, :broken, [:kaboom!]})

      :timer.sleep(100)

      state = :sys.get_state(dispatcher)

      refute Enum.any?(state.working)
      assert is_pid(state.pg)
    end
  end

  describe "handle_info/2 with job that raises error" do
    setup do
      {:ok, dispatcher} =
        Rihanna.JobDispatcher.start_link([db: Application.fetch_env!(:rihanna, :postgrex)], [])

      {:ok, %{dispatcher: dispatcher}}
    end

    test "marks job as failed", %{pg: pg} do
      {:ok, %{id: id}} = Rihanna.Job.enqueue({BadMFAMock, :perform, [:ok]})

      :timer.sleep(100)

      job = get_job_by_id(pg, id)

      assert %DateTime{} = job.failed_at
      assert "an exception was raised:\n    ** (RuntimeError) Kaboom!" <> _rest = job.fail_reason
    end

    test "removes task from state", %{dispatcher: dispatcher} do
      Rihanna.Job.enqueue({BadMFAMock, :perform, [:ok]})

      :timer.sleep(100)

      state = :sys.get_state(dispatcher)

      refute Enum.any?(state.working)
      assert is_pid(state.pg)
    end
  end

  describe "handle_info(:poll, state) with one scheduled job not yet due" do
    test "does not retrieve the job", %{pg: pg} do
      insert_job(pg, :scheduled_at)

      assert {:noreply, state} = JobDispatcher.handle_info(:poll, initial_state(pg))

      assert state.pg == pg
      assert map_size(state.working) == 0
    end
  end

  describe "dispatcher when job takes longer than poll interval" do
    setup do
      {:ok, dispatcher} =
        Rihanna.JobDispatcher.start_link([db: Application.fetch_env!(:rihanna, :postgrex)], [])

      {:ok, _} = Rihanna.Mocks.LongJob.Counter.start_link(:ok)
      {:ok, %{dispatcher: dispatcher}}
    end

    test "executes job only once" do
      Rihanna.enqueue(LongJob, :ok)

      :timer.sleep(600)

      assert Rihanna.Mocks.LongJob.Counter.get_count() == 1
    end
  end
end
