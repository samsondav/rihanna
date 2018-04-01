defmodule Rihanna.Config do
  def jobs_table_name() do
    Application.get_env(:rihanna, :jobs_table_name, "rihanna_jobs")
  end

  @doc """
  In Postgres, advisory locks are scoped to a classid.

  Here we use a random classid to prevent potential collisions with other users
  of the advisory locking system.

  In the unimaginably unlucky scenario that this conflicts with a lock classid
  that is already being used, you can change it here.
  """
  def pg_advisory_lock_class_id() do
    Application.get_env(:rihanna, :pg_advisory_lock_class_id, 1_759_441_536)
  end

  @doc """
  The maximum number of simultaneously executing workers for a dispatcher.

  50 is chosen as a sensible default. Tuning this might increase or decrease
  your throughput depending on a lot of factors including database churn and
  how many other dispatchers you are running.
  """
  def dispatcher_max_concurrency() do
    Application.get_env(:rihanna, :dispatcher_max_concurrency, 50)
  end

  @doc """
  How often the dispatcher should poll the database for new jobs (in milliseconds).

  Default is 100.

  Note that that actual poll interval in practice will be close to but not
  exactly this number of milliseconds for two reasons:

  1. A small amount of processing time for dispatching jobs is not included and
  will be added to the poll interval.
  2. A small, random amount of jitter is added to prevent multiple dispatchers started
  simultaneously from hitting the database at the same time.
  """
  def dispatcher_poll_interval() do
    Application.get_env(:rihanna, :poll_interval, 100)
  end
end
