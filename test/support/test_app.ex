defmodule TestApp do
  @moduledoc """
  An application used to start an Ecto Repo in test.
  """

  defmodule Repo do
    use Ecto.Repo, otp_app: :rihanna, adapter: Ecto.Adapters.Postgres
  end

  use Application

  def start(_type, _args) do
    {:ok, _} = Application.ensure_all_started(:ecto)
    {:ok, _} = Application.ensure_all_started(:postgrex)
    Supervisor.start_link([__MODULE__.Repo], strategy: :one_for_one)
  end
end
