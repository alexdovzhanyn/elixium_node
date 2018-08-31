defmodule ElixiumNodeApp do
  use Application
  alias Elixium.Store.Ledger
  alias Elixium.Store.Utxo
  alias Elixium.Blockchain
  alias Elixium.P2P.Peer

  def start(_type, _args) do
    IO.puts "starting"
    IO.inspect Application.get_env(:elixium_node, :logger)
    Ledger.initialize()
    Utxo.initialize()
    chain = Blockchain.initialize()

    {:ok, comm_pid} = ElixiumNode.start_link(chain)

    supervisor = Peer.initialize(comm_pid)

    ElixiumNode.set_supervisor(comm_pid, supervisor)

    {:ok, supervisor}
  end
end
