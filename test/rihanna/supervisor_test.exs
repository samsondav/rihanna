defmodule Rihanna.SupervisorTest do
  use ExUnit.Case, async: false

  describe "start_link/2" do
    test "boots the supervisor" do
      {:ok, _pid} =
        Rihanna.Supervisor.start_link(postgrex: Application.fetch_env!(:rihanna, :postgrex))
    end
  end
end
