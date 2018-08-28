defmodule ElixiumNodeTest do
  use ExUnit.Case
  doctest ElixiumNode

  test "greets the world" do
    assert ElixiumNode.hello() == :world
  end
end
