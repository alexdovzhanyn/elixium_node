defmodule Mix.Tasks.Node do
  use Mix.Task
  alias Elixium.Store.Ledger
  alias Elixium.Store.Utxo
  alias Elixium.Blockchain
  alias Elixium.P2P.Peer

  def run(_) do
    Ledger.initialize()
    Utxo.initialize()
    chain = Blockchain.initialize()

    {:ok, comm_pid} = ElixiumNode.start_link(chain)

    supervisor = Peer.initialize(comm_pid)

    ElixiumNode.set_supervisor(comm_pid, supervisor)

    Process.sleep(:infinity)
  end
end
