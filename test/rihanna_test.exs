defmodule RihannaTest do
  use ExUnit.Case
  doctest Rihanna

  import Rihanna
  import TestHelper

  setup_all [:create_jobs_table]

  describe "enqueue/1" do
    test "inserts a job to the DB" do
      :ok = Rihanna.enqueue({IO, :puts, ["Work, work, work, work, work."]})

    end

    test "shows helpful error for invalid argument" do
      expected_message = """
      Rihanna.Enqueue requires one argument in the form {mod, fun, args}.

      For example, to run IO.puts("Hello"):

      > Rihanna.enqueue({IO, :puts, ["Hello"]})
      """
      assert_raise ArgumentError, expected_message, fn ->
        enqueue("not a MFA")
      end
    end
  end
end
