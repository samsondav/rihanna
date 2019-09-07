defmodule ScheduleJobTest do
  use ExUnit.Case, async: false

  import Rihanna
  import TestHelper
  alias Rihanna.Mocks.MockJob

  setup_all [:create_jobs_table]

  @term {IO, :puts, ["Work, work, work, work, work."]}
  @due_at DateTime.from_naive!(~N[2018-08-01 14:00:00.000000], "Etc/UTC")

  describe "`schedule/2` with mfa at DateTime" do
    test "returns the job struct" do
      {:ok, job} = Rihanna.schedule(@term, at: @due_at)

      assert_job(job, @term, @due_at)
    end

    test "inserts the job to the DB", %{pg: pg} do
      {:ok, job} = Rihanna.schedule(@term, at: @due_at)

      job = get_job_by_id(pg, job.id)

      assert_job(job, @term, @due_at)
    end

    test "shows helpful error for invalid argument" do
      assert_raise FunctionClauseError, fn ->
        schedule("not a MFA", at: @due_at)
      end
    end

    test "shows helpful error for invalid schedule at argument" do
      assert_raise FunctionClauseError, fn ->
        schedule("not a MFA", at: ~N[2016-05-24 13:26:08.003])
      end
    end

    test "shows helpful error for missing schedule argument" do
      assert_raise FunctionClauseError, fn ->
        schedule("not a MFA", [])
      end
    end
  end

  describe "`schedule/2` with mfa in milliseconds" do
    test "returns the job struct" do
      expected_due_at = due_in(60_000)

      {:ok, job} = Rihanna.schedule(@term, in: :timer.minutes(1))

      assert_job(job, @term, expected_due_at)
    end

    test "inserts the job to the DB", %{pg: pg} do
      expected_due_at = due_in(3_600_000)

      {:ok, job} = Rihanna.schedule(@term, in: :timer.hours(1))

      job = get_job_by_id(pg, job.id)

      assert_job(job, @term, expected_due_at)
    end

    test "shows helpful error for invalid argument" do
      assert_raise FunctionClauseError, fn ->
        schedule("not a MFA", in: :timer.minutes(1))
      end
    end

    test "shows helpful error for invalid schedule in argument" do
      assert_raise FunctionClauseError, fn ->
        schedule("not a MFA", in: :invalid)
      end
    end
  end

  describe "`schedule/3` with module and arg" do
    test "returns the job struct" do
      {:ok, job} = Rihanna.schedule(MockJob, :arg, at: @due_at)

      assert_job(job, {Rihanna.Mocks.MockJob, :arg}, @due_at)
    end

    test "inserts the job to the DB", %{pg: pg} do
      {:ok, job} = Rihanna.schedule(MockJob, :arg, at: @due_at)

      job = get_job_by_id(pg, job.id)

      assert_job(job, {Rihanna.Mocks.MockJob, :arg}, @due_at)
    end

    test "shows helpful error for invalid argument" do
      assert_raise FunctionClauseError, fn ->
        schedule("not a module", [], at: @due_at)
      end
    end
  end

  defp assert_job(job, expected_term, expected_due_at) do
    assert %Rihanna.Job{} = job
    assert %DateTime{} = job.enqueued_at

    # Compare by seconds because time resolution is lost when persisting to the DB
    assert DateTime.to_unix(job.due_at) == DateTime.to_unix(expected_due_at)
    assert job.fail_reason |> is_nil
    assert job.failed_at |> is_nil
    assert job.term == expected_term
  end
end
