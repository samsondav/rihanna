defmodule Rihanna.Config do
  def jobs_table_name() do
    Application.get_env(:rihanna, :jobs_table_name, "rihanna_jobs")
  end
end
