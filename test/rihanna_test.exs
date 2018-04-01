defmodule RihannaTest do
  use ExUnit.Case, async: false
  doctest Rihanna

  import Rihanna
  import TestHelper

  setup_all [:create_jobs_table]

  @mfa {IO, :puts, ["Work, work, work, work, work."]}

  describe "enqueue/1" do
    setup do
      {:ok, _} =
        Postgrex.start_link(
          Keyword.put(
            Application.fetch_env!(:rihanna, :postgrex),
            :name,
            Rihanna.Postgrex
          )
        )

      :ok
    end

    test "returns the job struct" do
      {:ok, job} = Rihanna.enqueue(@mfa)

      assert %Rihanna.Job{} = job
      assert %DateTime{} = job.enqueued_at
      assert job.fail_reason |> is_nil
      assert job.failed_at |> is_nil
      assert job.mfa == @mfa
    end

    test "inserts the job to the DB", %{pg: pg} do
      {:ok, job} = Rihanna.enqueue(@mfa)

      job = get_job_by_id(pg, job.id)

      assert %Rihanna.Job{} = job
      assert %DateTime{} = job.enqueued_at
      assert job.fail_reason |> is_nil
      assert job.failed_at |> is_nil
      assert job.mfa == @mfa
    end

    test "shows helpful error for invalid argument" do
      expected_message = """
      Rihanna.Enqueue requires one argument in the form {mod, fun, args}.

      For example, to run IO.puts("Hello"):

      > Rihanna.enqueue({IO, :puts, ["Hello"]})
      """

      assert_raise ArgumentError, expected_message, fn ->
        enqueue("not a MFA")
      end
    end
  end
end
