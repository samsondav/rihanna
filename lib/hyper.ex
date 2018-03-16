defmodule Hyper do
  @moduledoc """
  Documentation for Hyper.
  """


  @doc """
  Hello world.

  ## Examples

      iex> Hyper.hello
      :world

  """
  def enqueue(mfa = {mod, fun, args}) do
    job = %Hyper.Job{
      mfa: mfa,
      state: "ready_to_run"
    }
    NestDB.Repo.insert(job)
  end
end
