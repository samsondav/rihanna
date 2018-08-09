defmodule Rihanna.JobsTableIndexing do
  @moduledoc """
  Benchmark to compare the affect of an index applied to the Rihanna jobs table.

  To run this benchmark:

      $ MIX_ENV=test mix run benchmarks/jobs_table_indexing.exs
  """

  def benchmark do
    Benchee.run(
      %{
        "with index" => {
          &lock_job/1,
          before_scenario: fn %{pg: pg} = input ->
            create_index(pg)
            input
          end
        },
        "no index" => {
          &lock_job/1,
          before_scenario: fn input ->
            input
          end
        }
      },
      inputs: %{
        "10 x ready, scheduled, due, and failed jobs" => 10,
        "100 x ready, scheduled, due, and failed jobs" => 100,
        "1,000 x ready, scheduled, due, and failed jobs" => 1_000,
        "10,000 x ready, scheduled, due, and failed jobs" => 10_000
      },
      time: 5,

      # Recreate the jobs table and enqueue jobs specified in the input data.
      before_scenario: fn input ->
        {:ok, pg} = recreate_jobs_table()

        enqueue_jobs(pg, input)

        %{input: input, pg: pg}
      end,

      # Shutdown Postgrex connection to release all advisory locks
      after_scenario: fn %{pg: pg} = input ->
        shutdown(pg)

        input
      end,

      # Insert another job after each benchmark run as we only want to time lock
      # acquisition while there are jobs queued.
      after_each: fn %{pg: pg} = input ->
        TestHelper.insert_job(pg, :ready_to_run)

        input
      end
    )
  end

  defp lock_job(%{pg: pg} = input) do
    Rihanna.Job.lock(pg)

    input
  end

  defp enqueue_jobs(pg, count) do
    for i <- 1..count do
      TestHelper.insert_job(pg, :ready_to_run)
      TestHelper.insert_job(pg, :scheduled_at)
      TestHelper.insert_job(pg, :schedule_due)
      TestHelper.insert_job(pg, :failed)
    end
  end

  defp create_index(pg) do
    Postgrex.query!(
      pg,
      """
      CREATE INDEX rihanna_poll_idx ON rihanna_jobs (due_at)
      WHERE (failed_at IS NULL);
      """,
      []
    )
  end

  defp recreate_jobs_table do
    {:ok, %{pg: pg}} = TestHelper.create_jobs_table([])

    {:ok, pg}
  end

  defp shutdown(pid) do
    Process.unlink(pid)
    Process.exit(pid, :shutdown)

    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    end
  end
end

Rihanna.JobsTableIndexing.benchmark()
