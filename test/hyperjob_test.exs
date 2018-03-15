defmodule HyperjobTest do
  use ExUnit.Case
  doctest Hyperjob

  test "greets the world" do
    assert Hyperjob.hello() == :world
  end
end
