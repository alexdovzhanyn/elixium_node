defmodule ElixiumNode do
  use GenServer
  require Logger
  alias Elixium.Validator
  alias Elixium.Blockchain
  alias Elixium.Blockchain.Block
  alias Elixium.Store.Ledger
  alias Elixium.P2P.Peer
  alias Elixium.Pool.Orphan
  require IEx

  def start_link do
    GenServer.start_link(__MODULE__, {})
  end

  def init(_state), do: {:ok, %{transactions: []}}

  def handle_info(msg, state) do
    state =
      case msg do
        header = %{type: "BLOCK_HEADER"} ->
          IO.inspect header
          state
        block = %{type: "BLOCK"} ->
          IO.inspect(block, limit: :infinity)
          # Check if we've already received a block at this index. If we have,
          # diff it against the one we've stored. If we haven't, check to see
          # if this index is the next index in the chain. In the case that its
          # not, we've likely found a new longest chain, so we need to evaluate
          # whether or not we want to switch to that chain
          case Ledger.block_at_height(block.index) do
            :none ->
              last_block = Ledger.last_block()

              if block.index == last_block.index + 1 && block.previous_hash == last_block.hash do
                # TODO: Revisit this logic; when receiving a block at the current expected
                # index, we're dropping the block since we don't check if the block is
                # building on a fork, we just assume that it's building on our chain,
                # so validation fails, since the blocks previous_hash will be different.
                evaluate_new_block(block)
              else
                evaluate_chain_swap(block)
              end
            stored_block -> handle_possible_fork(block, stored_block)
          end
          state
        transaction = %{type: "TRANSACTION"} ->
          IO.inspect(transaction)

          # Don't re-validate and re-send a transaction we've already received.
          # This eliminates looping issues where nodes pass the same transaction
          # back and forth.
          new_state =
            if !Enum.member?(state.transactions, transaction) && Validator.valid_transaction?(transaction) do
              Logger.info("Received valid transaction #{transaction.id}. Forwarding to peers.")
              Peer.gossip("TRANSACTION", transaction)

              %{state | transactions: [transaction | state.transactions]}
            else
              state
            end

        _ ->
          IO.puts "Didnt match"
          state
      end

    {:noreply, state}
  end

  @spec evaluate_new_block(Block) :: none
  defp evaluate_new_block(block) do
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
  end

  @spec handle_possible_fork(Block, Block) :: none
  defp handle_possible_fork(block, existing_block) do
    Logger.info("Already have block with index #{existing_block.index}. Performing block diff...")

    case Block.diff_header(existing_block, block) do
      # If there is no diff, just skip the block
      [] ->
        Logger.info("Same block.")
        :no_diff
      diff ->
        Logger.warn("Fork block received! Checking existing orphan pool...")

        # Is this a fork of the most recent block? If it is, we don't have an orphan
        # chain to build on...
        if Ledger.last_block().index == block.index do
          # TODO: validate orphan block in context of its chain state before adding it
          Logger.warn("Received fork of current block")
          Orphan.add(block)
        else
          # Check the orphan pool for blocks at the previous height whose hash this
          # orphan block references as a previous_hash
          case Orphan.blocks_at_height(block.index - 1) do
            [] ->
              # We don't know of any ORPHAN blocks that this block might be referencing.
              # Perhaps this is a fork of a block that we've accepted as canonical into our
              # chain?
              case Ledger.retrieve_block(block.previous_hash) do
                :not_found ->
                  # If this block doesn't reference and blocks that we know of, we can not
                  # build a chain using this block -- we can't validate this block at all.
                  # Our only option is to drop the block. Realistically we shouldn't ever
                  # get into this situation unless a malicious actor has sent us a fake block.
                  Logger.warn("Received orphan block with no reference to a known block. Dropping orphan")
                canonical_block ->
                  # This block is a fork of a canonical block.
                  # TODO: Validate this fork in context of the chain state at this point in time
                  Logger.warn("Fork of canonical block received")
                  Orphan.add(block)
              end
            orphan_blocks ->
              # This block might be a fork of a block that we have stored in our
              # orphan pool
              Logger.warn("Possibly extension of existing fork")
              Orphan.add(block)
          end
        end
    end
  end

  # Check that a given fork is valid, and if it is, swap to the fork
  @spec evaluate_chain_swap(Block) :: none
  defp evaluate_chain_swap(block) do
    # Rebuild the chain backwards until reaching a point where we agree on the
    # same blocks as the fork does.
    {fork_chain, fork_source} = rebuild_fork_chain(block)

    # Traverse the fork chain, making sure each block is valid within its own
    # context.
    # TODO: Make validation difficulty dynamic
    {_, validation_results} =
      fork_chain
      |> Enum.scan({fork_source, []}, fn (block, {last, results}) ->
        {block, [Validator.is_block_valid?(block, 5.0, last) | results]}
      end)
      |> List.last()

    # Ensure that every block passed validation
    if Enum.all?(validation_results, &(&1 == :ok)) do
      Logger.info("Candidate fork chain valid. Switching.")

      fork_chain
      |> Enum.reverse()
      |> Enum.flat_map(&parse_transaction_inputs/1)
      |> IO.inspect
      # TODO: continue this.
    else
      Logger.info("Evaluated candidate fork chain. Not viable for switch.")
    end
  end

  def rebuild_fork_chain(chain) when is_list(chain) do
    case Orphan.blocks_at_height(hd(chain).index - 1) do
      [] ->
        IO.puts "got to false"
        false
      orphan_blocks ->
        orphan_blocks
        |> Enum.filter(fn {_, block} -> block.hash == hd(chain).previous_hash end)
        |> Enum.find_value(fn {_, candidate_orphan}->
          # Check if we agree on a previous_hash
          case Ledger.retrieve_block(candidate_orphan.previous_hash) do
            # We need to dig deeper...
            :not_found -> rebuild_fork_chain([candidate_orphan | chain])
            # We found the source of this fork. Return the chain we've accumulated
            fork_source -> {[candidate_orphan | chain], fork_source}
          end
        end)
    end
  end

  def rebuild_fork_chain(block), do: rebuild_fork_chain([block])

  # Return a list of all transaction inputs for every transaction in this block
  @spec parse_transaction_inputs(Block) :: list
  defp parse_transaction_inputs(block) do
    block.transactions
    |> Enum.flat_map(&(&1.inputs))
    |> Enum.map(&(Map.delete(&1, :signature)))
  end
end
