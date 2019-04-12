defmodule ElixiumNode.Supervisor do
  use Supervisor
  alias Elixium.Store.Oracle

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    Oracle.start_link(Elixium.Store.Peer)
    port = Application.get_env(:elixium_core, :port)
    handlers = Application.get_env(:elixium_core, :max_connections)
    peers = Elixium.Store.Peer.find_potential_peers()

    children = [
      {Pico.Client.Supervisor, {ElixiumNode.Router, peers, port, handlers}}
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
