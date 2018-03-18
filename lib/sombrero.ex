defmodule Sombrero do
  @moduledoc """
  Documentation for Sombrero.
  """
  def enqueue(mfa = {mod, fun, args}) do
    job = %Sombrero.Job{
      mfa: mfa,
      state: "ready_to_run"
    }

    Sombrero.Repo.insert(job)
  end
end
