defmodule ElixiumNodeApp do
  use Application
  alias Elixium.Store.Ledger
  alias Elixium.Store.Utxo
  alias Elixium.Blockchain
  alias Elixium.P2P.Peer
  alias Elixium.Pool.Orphan

  def start(_type, _args) do
    Ledger.initialize()
    Utxo.initialize()
    Orphan.initialize()
    Blockchain.initialize()

    {:ok, comm_pid} = ElixiumNode.start_link()

    if port = Application.get_env(:elixium_node, :port) do
      Peer.initialize(comm_pid, port)
    else
      Peer.initialize(comm_pid)
    end

    {:ok, self()}
  end
end
