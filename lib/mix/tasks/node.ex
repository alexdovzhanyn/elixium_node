defmodule Mix.Tasks.Node do
  use Mix.Task

  def run(_) do
     ElixiumNode.start_link()
     Process.sleep(:infinity)
   end
end
