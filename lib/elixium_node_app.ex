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

    if port = Application.get_env(:elixium_node, :port) do
      Peer.initialize(comm_pid, port)
    else
      Peer.initialize(comm_pid)
    end

    {:ok, self()}
  end
end
