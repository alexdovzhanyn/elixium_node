defmodule ElixiumNode do
  use GenServer
  require Logger
  alias Elixium.Validator
  alias Elixium.Blockchain
  alias Elixium.Blockchain.Block
  alias Elixium.Store.Ledger
  alias Elixium.P2P.Peer

  def start_link(chain) do
    GenServer.start_link(__MODULE__, {})
  end

  def init(_state), do: {:ok, {}}

  def handle_info(msg, _state) do
    case msg do
      header = %{type: "BLOCK_HEADER"} ->
        IO.inspect header
      block = %{type: "BLOCK"} ->
        IO.inspect Block.header(block)

        # Check if we've already received a block at this index. If we have,
        # diff it against the one we've stored.
        case Ledger.block_at_height(block.index) do
          :none ->
            last_block = Ledger.last_block()

            difficulty =
              if rem(block.index, Blockchain.diff_rebalance_offset()) == 0 do
                new_difficulty = Blockchain.recalculate_difficulty() + last_block.difficulty
                IO.puts("Difficulty recalculated! Changed from #{last_block.difficulty} to #{new_difficulty}")
                new_difficulty
              else
                last_block.difficulty
              end

            case Validator.is_block_valid?(block, difficulty) do
              :ok ->
                Logger.info("Block #{block.index} valid.")
                Blockchain.add_block(block)
                Peer.gossip("BLOCK", block)
              err -> Logger.info("Block #{block.index} invalid!")
            end
          stored_block ->
            Logger.info("Already have block with index #{block.index}. Performing block diff...")

            case Block.diff_header(stored_block, block) do
              [] -> Logger.info("Exact same block. Skipping")
              diff ->
                Logger.warn("Fork block received! Checking existing fork pool...")
            end
        end
      _ ->
        IO.puts "Didnt match"
    end

    {:noreply, {}}
  end
end
