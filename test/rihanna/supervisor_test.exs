defmodule Rihanna.SupervisorTest do
  use ExUnit.Case, async: false
  doctest Rihanna

  describe "start_link/2" do
    test "boots the supervisor" do
      {:ok, _pid} =
        Rihanna.Supervisor.start_link(
          postgrex: [
            username: "nested",
            password: "nested",
            database: "rihanna_db",
            hostname: "127.0.0.1",
            port: 54321
          ]
        )
    end
  end
end
