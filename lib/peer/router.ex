defmodule ElixiumNode.Router do
  use Pico.Client.Router
  require Logger
  alias Elixium.Node.LedgerManager
  alias Elixium.Store.Ledger
  alias Elixium.Pool.Orphan
  alias Elixium.Block
  alias Elixium.Transaction
  alias Elixium.Validator
  alias Elixium.Store.Oracle

  message "BLOCK", block do
    block = Block.sanitize(block)

    case LedgerManager.handle_new_block(block) do
      :ok ->
        # We've received a valid block. We need to gossip this block to all the
        # nodes we know of.
        Logger.info("Received valid block #{block.hash} at index #{:binary.decode_unsigned(block.index)}.")
        Pico.broadcast("BLOCK", block)

        known_transactions = SharedState.get(:transactions) -- [block.transactions]
        SharedState.set(:transactions, known_transactions)

      :gossip ->
        # For one reason or another, we want to gossip this block. (Perhaps this is a fork block)
        Pico.broadcast("BLOCK", block)

      {:missing_blocks, fork_chain} ->
        # We've discovered a fork, but we can't rebuild the fork chain without
        # some blocks. Let's request them from our peer.

        Pico.message(conn, "BLOCK_QUERY_REQUEST", %{index: :binary.decode_unsigned(hd(fork_chain).index) - 1})

      :invalid ->
        Logger.info("Recieved invalid block at index #{:binary.decode_unsigned(block.index)}.")

      :ignore -> :ignore
    end
  end

  message "BLOCK_QUERY_REQUEST", %{index: index} do
    Pico.message(conn, "BLOCK_QUERY_RESPONSE", Ledger.block_at_height(index))
  end

  message "BLOCK_QUERY_RESPONSE", response do
    orphans_ahead =
      Ledger.last_block().index
      |> :binary.decode_unsigned()
      |> Kernel.+(1)
      |> Orphan.blocks_at_height()
      |> length()

    if orphans_ahead > 0 do
      # If we have an orphan with an index that is greater than our current latest
      # block, we're likely here trying to rebuild the fork chain and have requested
      # a block that we're missing.
      # TODO: FETCH BLOCKS
    end
  end

  message "BLOCK_BATCH_QUERY_REQUEST", %{starting_at: start} do
    # TODO: This is a possible DOS vulnerability if an attacker requests a very
    # high amount of blocks. Need to figure out a better way to do this; maybe
    # we need to limit the maximum amount of blocks a peer is allowed to request.
    last_block = Ledger.last_block()

    blocks =
      if last_block != :err && start <= :binary.decode_unsigned(last_block.index) do
        start
        |> Range.new(:binary.decode_unsigned(last_block.index))
        |> Enum.map(&Ledger.block_at_height/1)
        |> Enum.filter(& &1 != :none)
      else
        []
      end

    Pico.message(conn, "BLOCK_BATCH_QUERY_RESPONSE", %{blocks: blocks})
  end

  message "BLOCK_BATCH_QUERY_RESPONSE", %{blocks: blocks} do
    blocks_count = length(blocks)

    if blocks_count > 0 do
      Logger.info("Recieved #{blocks_count} blocks from peer.")

      blocks
      |> Enum.with_index()
      |> Enum.each(fn {block, i} ->
        block = Block.sanitize(block)

        if LedgerManager.handle_new_block(block) == :ok do
          IO.write("Syncing blocks #{round(((i + 1) / blocks_count) * 100)}% [#{i + 1}/#{blocks_count}]\r")
        end
      end)

      IO.write("Block Sync Complete")
    end
  end

  message "TRANSACTION", transaction do
    transaction = Transaction.sanitize(transaction)
    known_transactions = SharedState.get(:transactions)

    if Validator.valid_transaction?(transaction) do
      if transaction not in known_transactions do
        <<shortid::bytes-size(20), _rest::binary>> = transaction.id
        Logger.info("Received transaction \e[32m#{shortid}...\e[0m")
        Pico.broadcast("TRANSACTION", transaction)

        SharedState.set(:transactions, [transaction | known_transactions])
      end
    else
      Logger.info("Received Invalid Transaction. Ignoring.")
    end
  end

  message "PORT_RECONNECTION_QUERY", _ do
    port = Application.get_env(:elixium_core, :port)

    Pico.message(conn, "PORT_RECONNECTION_RESPONSE", %{port: port})
  end

  message "PORT_RECONNECTION_RESPONSE", %{port: port} do

  end

  message "PEER_QUERY_REQUEST", _ do
    peers =
      :"Elixir.Elixium.Store.PeerOracle"
      |> GenServer.call({:load_known_peers, []})
      |> Enum.take(8)

    Pico.message(conn, "PEER_QUERY_RESPONSE", %{peers: peers})
  end

  message "PEER_QUERY_RESPONSE", %{peers: peers} do
    Enum.each(peers, fn peer ->
      GenServer.call(:"Elixir.Elixium.Store.PeerOracle", {:save_known_peer, [peer]})
    end)
  end

end
