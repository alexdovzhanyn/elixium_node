defmodule ElixiumNode.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    children = [
      {Elixium.Node.Supervisor, [:"Elixir.ElixiumNode.PeerRouter"]},
      ElixiumNode.PeerRouter.Supervisor
    ]

    children =
      if Application.get_env(:elixium_node, :rpc) do
        [ElixiumNode.RPC.Supervisor | children]
      else
        children
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
