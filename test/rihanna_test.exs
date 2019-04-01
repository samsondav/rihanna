defmodule RihannaTest do
  use ExUnit.Case, async: false
  doctest Rihanna

  import Rihanna
  import TestHelper
  alias Rihanna.Mocks.MockJob
  require TemporaryEnv

  @term {IO, :puts, ["Work, work, work, work, work."]}

  describe "`enqueue/1` with mfa" do
    setup [:create_jobs_table]

    test "returns the job struct" do
      {:ok, job} = Rihanna.enqueue(@term)

      assert %Rihanna.Job{} = job
      assert %DateTime{} = job.enqueued_at
      assert job.due_at |> is_nil
      assert job.fail_reason |> is_nil
      assert job.failed_at |> is_nil
      assert job.priority == 0
      assert job.term == @term
    end

    test "inserts the job to the DB", %{pg: pg} do
      {:ok, job} = Rihanna.enqueue(@term)

      job = get_job_by_id(pg, job.id)

      assert %Rihanna.Job{} = job
      assert %DateTime{} = job.enqueued_at
      assert job.due_at |> is_nil
      assert job.fail_reason |> is_nil
      assert job.failed_at |> is_nil
      assert job.priority == 0
      assert job.term == @term
    end

    test "shows helpful error for invalid argument" do
      expected_message = """
      Rihanna.Enqueue requires either one argument in the form {mod, fun, args} or
      two arguments of a module implementing Rihanna.Job and its arg.

      For example, to run IO.puts("Hello"):

      > Rihanna.enqueue({IO, :puts, ["Hello"]})

      Or, if you have a job called MyJob that implements the Rihanna.Job behaviour:

      > Rihanna.enqueue(MyJob, arg)
      """

      assert_raise ArgumentError, expected_message, fn ->
        enqueue("not a MFA")
      end
    end
  end

  describe "`enqueue/2` with module and arg" do
    setup [:create_jobs_table]

    test "returns the job struct" do
      {:ok, job} = Rihanna.enqueue(MockJob, :arg)

      assert %Rihanna.Job{} = job
      assert %DateTime{} = job.enqueued_at
      assert job.due_at |> is_nil
      assert job.fail_reason |> is_nil
      assert job.failed_at |> is_nil
      assert job.priority == 0
      assert job.term == {Rihanna.Mocks.MockJob, :arg}
    end

    test "inserts the job to the DB", %{pg: pg} do
      {:ok, job} = Rihanna.enqueue(MockJob, :arg)

      job = get_job_by_id(pg, job.id)

      assert %Rihanna.Job{} = job
      assert %DateTime{} = job.enqueued_at
      assert job.due_at |> is_nil
      assert job.fail_reason |> is_nil
      assert job.failed_at |> is_nil
      assert job.priority == 0
      assert job.term == {Rihanna.Mocks.MockJob, :arg}
    end

    test "shows helpful error for invalid argument" do
      expected_message = """
      Rihanna.Enqueue requires either one argument in the form {mod, fun, args} or
      two arguments of a module implementing Rihanna.Job and its arg.

      For example, to run IO.puts("Hello"):

      > Rihanna.enqueue({IO, :puts, ["Hello"]})

      Or, if you have a job called MyJob that implements the Rihanna.Job behaviour:

      > Rihanna.enqueue(MyJob, arg)
      """

      assert_raise ArgumentError, expected_message, fn ->
        enqueue("not a module", :arg)
      end
    end
  end

  describe "user specified producer_postgres_connection" do
    setup [:create_jobs_table]

    test "`enqueue/2`, `get_job_by_id/1`, `delete/1` using an Ecto Repo", %{pg: pg} do
      TemporaryEnv.put :rihanna, :producer_postgres_connection, {Ecto, TestApp.Repo} do
        assert Rihanna.Config.producer_postgres_connection() == {Ecto, TestApp.Repo}

        TestApp.Repo.transaction(fn ->
          {:ok, job} = Rihanna.enqueue(MockJob, :arg)

          # Repo conn is being used
          assert job = get_job_by_id(TestApp.Repo, job.id)
          refute get_job_by_id(pg, job.id)

          assert %Rihanna.Job{} = job
          assert %DateTime{} = job.enqueued_at
          assert job.due_at |> is_nil
          assert job.fail_reason |> is_nil
          assert job.failed_at |> is_nil
          assert job.priority == 0
          assert job.term == {Rihanna.Mocks.MockJob, :arg}

          assert {:ok, _} = Rihanna.delete(job.id)

          refute get_job_by_id(pg, job.id)
        end)
      end
    end

    test "`enqueue/2`, `get_job_by_id/1`, `delete/1` using a Postgrex conn", %{pg: pg} do
      TemporaryEnv.put :rihanna, :producer_postgres_connection, {Postgrex, pg} do
        assert Rihanna.Config.producer_postgres_connection() == {Postgrex, pg}

        {:ok, job} = Rihanna.enqueue(MockJob, :arg)

        assert job = get_job_by_id(pg, job.id)

        assert %Rihanna.Job{} = job
        assert %DateTime{} = job.enqueued_at
        assert job.due_at |> is_nil
        assert job.fail_reason |> is_nil
        assert job.failed_at |> is_nil
        assert job.priority == 0
        assert job.term == {Rihanna.Mocks.MockJob, :arg}

        assert {:ok, _} = Rihanna.delete(job.id)

        refute get_job_by_id(pg, job.id)
      end
    end
  end

  describe "delete/1" do
    setup [:create_jobs_table]

    test "deletes a job", %{pg: pg} do
      {:ok, job} = Rihanna.enqueue(MockJob, :arg)

      assert {:ok,
              %Rihanna.Job{
                due_at: nil,
                enqueued_at: _,
                fail_reason: nil,
                failed_at: nil,
                id: 1,
                priority: 19,
                term: {Rihanna.Mocks.MockJob, :arg}
              }} = Rihanna.delete(job.id)

      refute get_job_by_id(pg, job.id)
    end

    test "returns error if job does not exist", %{pg: pg} do
      assert Rihanna.delete(1) == {:error, :job_not_found}
      refute get_job_by_id(pg, 1)
    end
  end

  describe "without a Rihanna jobs table" do
    setup [:drop_jobs_table]

    test "warn when `Rihanna.enqueue` used" do
      assert_raise ArgumentError, ~r/^The Rihanna jobs table must be created./, fn ->
        Rihanna.enqueue(@term)
      end
    end

    test "warn when `Rihanna.schedule` used" do
      assert_raise ArgumentError, ~r/^The Rihanna jobs table must be created./, fn ->
        Rihanna.schedule(@term, at: DateTime.utc_now())
      end
    end
  end
end
