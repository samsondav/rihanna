defmodule Sombrero.WorkerHeartbeat do
  require Logger
  use GenServer
  require Ecto.Query, as: Query

  # Issue heartbeat once half of the grace time has expired
  @hearbeat_interval :timer.seconds(Sombrero.Job.grace_time_seconds() / 2)

  def start_link(job) do
    GenServer.start_link(__MODULE__, %{job: job})
  end

  def init(state) do
    start_timer()
    {:ok, state}
  end

  def handle_info(:heartbeat, state = %{job: job}) do
    Logger.debug("HEARTBEAT from #{inspect(self())}")
    extend_expiry(job)
    {:noreply, state}
  end

  defp extend_expiry(%{id: id}) do
    now = DateTime.utc_now()
    new_expiry = Sombrero.Job.expires_at(now)

    {1, nil} =
      Sombrero.Repo.update_all(
        Query.from(Sombrero.Job, where: [id: ^id]),
        set: [
          expires_at: new_expiry,
          updated_at: now
        ]
      )
  end

  defp start_timer() do
    {:ok, _ref} = :timer.send_interval(@hearbeat_interval, :heartbeat)
  end
end
