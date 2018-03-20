defmodule Sombrero.Config do
  def jobs_table_name() do
    Application.get_env(:sombrero, :jobs_table_name, "sombrero_jobs")
  end
end
