defmodule Rihanna.Mocks do
  defmodule LongJob do
    @behaviour Rihanna.Job

    def perform(_) do
      LongJob.Counter.increment()
      :timer.sleep(500)
      :ok
    end
  end

  defmodule LongJob.Counter do
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> 0 end, name: __MODULE__)
    end

    def increment() do
      Agent.update(__MODULE__, fn count ->
        count + 1
      end)
    end

    def get_count() do
      Agent.get(__MODULE__, & &1)
    end
  end

  defmodule BehaviourMock do
    @behaviour Rihanna.Job

    def perform([pid, msg]) do
      Process.send(pid, {msg, self()}, [])
      :ok
    end
  end

  defmodule ErrorTupleBehaviourMock do
    @behaviour Rihanna.Job

    def perform([pid, msg]) do
      Process.send(pid, {msg, self()}, [])
      {:error, %{message: "failed for some reason"}}
    end

    def after_error({:error, _}, [pid, _]) do
      Process.send(pid, "After error callback", [])
    end
  end

  defmodule ErrorBehaviourMock do
    @behaviour Rihanna.Job

    def perform([pid, msg]) do
      Process.send(pid, {msg, self()}, [])
      :error
    end

    def after_error(:error, [pid, _]) do
      Process.send(pid, "After error callback", [])
    end
  end

  defmodule ErrorBehaviourWithBadAfterErrorMock do
    @behaviour Rihanna.Job

    def perform([pid, msg]) do
      Process.send(pid, {msg, self()}, [])
      :error
    end

    def after_error(:error, [_pid, _]) do
      raise "Kaboom!"
    end
  end

  defmodule BadBehaviourWithBadAfterErrorMock do
    @behaviour Rihanna.Job

    def perform(_) do
      raise "Kaboom!"
    end

    def after_error(_reason, _args) do
      raise "Double kaboom!"
    end
  end

  defmodule MFAMock do
    def fun(pid, msg) do
      Process.send(pid, {msg, self()}, [])
    end
  end

  defmodule BadMFAMock do
    @behaviour Rihanna.Job

    def perform(_) do
      raise "Kaboom!"
    end

    def after_error(_reason, [pid, _]) do
      Process.send(pid, "After error callback", [])
    end
  end

  defmodule MockJob do
    @behaviour Rihanna.Job

    def perform(arg) do
      {:ok, arg}
    end
  end

  defmodule MockRetriedJob do
    @behaviour Rihanna.Job

    def perform([pid, msg]) do
      Process.send(pid, {msg, self()}, [])
      {:error, "Failed on retry"}
    end

    # Retry once
    def retry_at(_reason, _arg, 0) do
      # Retry immediately
      {:ok, DateTime.utc_now()}
    end

    def retry_at(_, _, _) do
      :noop
    end
  end

  defmodule ErrorBehaviourMockWithNoErrorCallback do
    @behaviour Rihanna.Job

    def perform([pid, msg]) do
      Process.send(pid, {msg, self()}, [])
      :error
    end
  end
end
