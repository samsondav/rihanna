defmodule Sombrero.Supervisor do
  use Supervisor

  @moduledoc """
  TODO: Write some documentation
  """

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    children = [
      worker(Postgrex.Notifications, [Sombrero.Repo.config() ++ [name: Sombrero.PGNotifier]]),
      Sombrero.Repo,
      Sombrero.Manager
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
