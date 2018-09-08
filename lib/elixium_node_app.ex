defmodule ElixiumNodeApp do
  use Application
  alias Elixium.Store.Ledger
  alias Elixium.Store.Utxo
  alias Elixium.Blockchain
  alias Elixium.P2P.Peer

  def start(_type, _args) do
    Ledger.initialize()
    Utxo.initialize()
    chain = Blockchain.initialize()

    {:ok, comm_pid} = ElixiumNode.start_link(chain)

    Peer.initialize(comm_pid)

    {:ok, self()}
  end
end
