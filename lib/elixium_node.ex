defmodule ElixiumNode do
  use GenServer
  alias Elixium.Store.Ledger
  alias Elixium.Store.Utxo
  alias Elixium.Blockchain
  alias Elixium.P2P.Peer

  def start_link do
    Ledger.initialize()
    Utxo.initialize()
    chain = Blockchain.initialize()

    supervisor = Peer.initialize
    GenServer.start_link(__MODULE__, {supervisor, chain})
  end

  def init(options) when is_tuple(options) do
    {:ok, options}
  end

  def handle_info(msg, {supervisor, chain}) do
    case msg do
      t ->
        IO.inspect t
    end
  end
end
