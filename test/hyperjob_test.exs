defmodule SombreroTest do
  use ExUnit.Case
  doctest Sombrero

  test "greets the world" do
    assert Sombrero.hello() == :world
  end
end
