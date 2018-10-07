defmodule ElixiumNode do
  use GenServer
  require Logger
  alias Elixium.Validator
  alias Elixium.Blockchain
  alias Elixium.Blockchain.Block
  alias Elixium.Store.Ledger
  alias Elixium.P2P.Peer
  alias Elixium.Pool.Orphan
  alias Elixium.Store.Utxo
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

    current_utxos_in_pool = Utxo.retrieve_all_utxos()

    # Blocks which need to be reversed
    blocks_to_reverse =
      (fork_source.index + 1)..Ledger.last_block().index
      |> Enum.map(&Ledger.block_at_height/1)

    # Find transaction inputs that need to be reversed
    all_canonical_transaction_inputs_since_fork =
      Enum.flat_map(blocks_to_reverse, &parse_transaction_inputs/1)

    canon_output_txoids =
      blocks_to_reverse
      |> Enum.flat_map(&parse_transaction_outputs/1)
      |> Enum.map(& &1.txoid)

    # Pool at the time of fork is basically just current pool plus all inputs
    # used in canon chain since fork, minus all outputs created in after fork
    # (this will also remove inputs that were created as outputs and used in
    # the fork)
    pool =
      current_utxos_in_pool ++ all_canonical_transaction_inputs_since_fork
      |> Enum.filter(&(!Enum.member?(canon_output_txoids, &1.txoid)))

    # Traverse the fork chain, making sure each block is valid within its own
    # context.
    {_, final_contextual_pool, validation_results} =
      fork_chain
      |> Enum.scan({fork_source, pool, []}, &validate_in_context/2)
      |> List.last()

    # Ensure that every block passed validation
    if Enum.all?(validation_results, & &1) do
      Logger.info("Candidate fork chain valid. Switching.")

      # Add everything in final_contextual_pool that is not also in current_utxos_in_pool
      Enum.each(final_contextual_pool -- current_utxos_in_pool, &Utxo.add_utxo/1)

      # Remove everything in current_utxos_in_pool that is not also in final_contextual_pool
      current_utxos_in_pool -- final_contextual_pool
      |> Enum.map(& &1.txoid)
      |> Enum.each(&Utxo.remove_utxo/1)

      # Drop canon chain blocks from the ledger, add them to the orphan pool
      # in case the chain gets revived by another miner
      Enum.each(blocks_to_reverse, fn blk ->
        Orphan.add(blk)
        Ledger.drop_block(blk)
      end)

      # Remove fork chain from orphan pool; now it becomes the canon chain,
      # so we add its blocks to the ledger
      Enum.each(fork_chain, fn blk ->
        Ledger.append_block(blk)
        Orphan.remove(blk)
      end)
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

  @spec parse_transaction_outputs(Block) :: list
  defp parse_transaction_outputs(block), do: Enum.flat_map(block.transactions, &(&1.outputs))

  defp validate_in_context(block, {last, pool, results}) do
    # TODO: Make validation difficulty dynamic
    valid = :ok == Validator.is_block_valid?(block, 5.0, last, &(pool_check(pool, &1)))

    # Update the contextual utxo pool by removing spent inputs and adding
    # unspent outputs from this block. The following block will use the updated
    # contextual pool for utxo validation
    updated_pool =
      if valid do
        block_input_txoids =
          block
          |> parse_transaction_inputs()
          |> Enum.map(& &1.txoid)

        block_outputs = parse_transaction_outputs(block)

        Enum.filter(pool ++ block_outputs, &(!Enum.member?(block_input_txoids, &1.txoid)))
      else
        pool
      end

    {block, updated_pool, [valid | results]}
  end

  @spec pool_check(list, map) :: true | false
  defp pool_check(pool, utxo) do
    case Enum.find(pool, false, & &1.txoid == utxo.txoid) do
      false -> false
      txo_in_pool -> utxo.amount == txo_in_pool.amount && utxo.addr == txo_in_pool.addr
    end
  end
end
