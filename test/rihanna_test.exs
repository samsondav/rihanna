defmodule RihannaTest do
  use ExUnit.Case, async: false
  doctest Rihanna

  import Rihanna
  import TestHelper
  alias Rihanna.Mocks.MockJob

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
