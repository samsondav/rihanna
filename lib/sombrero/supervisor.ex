defmodule Sombrero.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    children = [
      Sombrero.Repo,
      Sombrero.Manager
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
