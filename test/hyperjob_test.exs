defmodule HyperTest do
  use ExUnit.Case
  doctest Hyper

  test "greets the world" do
    assert Hyper.hello() == :world
  end
end
