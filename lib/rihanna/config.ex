defmodule Rihanna.Config do
  def jobs_table_name() do
    Application.get_env(:rihanna, :jobs_table_name, "rihanna_jobs")
  end

  def pg_advisory_lock_class_id() do
    Application.get_env(:rihanna, :pg_advisory_lock_class_id, 42)
  end
end
