defmodule ElixiumNode do
  use GenServer
  require Logger
  alias Elixium.Validator
  alias Elixium.Blockchain
  alias Elixium.Blockchain.Block

  def start_link(chain) do
    GenServer.start_link(__MODULE__, chain)
  end

  def init(chain) when is_list(chain) do
    {:ok, {chain}}
  end

  def handle_cast({:set_supervisor, peer_supervisor}, {chain}) do
    {:noreply, {peer_supervisor, chain}}
  end

  def handle_info(msg, {supervisor, chain}) do
    chain =
      case msg do
        header = %{type: "BLOCK_HEADER"} ->
          IO.inspect header
          chain
        block = %{type: "BLOCK"} ->
          IO.inspect Block.header(block)

          difficulty = List.first(chain).difficulty

          difficulty =
            if rem(block.index, Blockchain.diff_rebalance_offset()) == 0 do
              new_difficulty = Blockchain.recalculate_difficulty(chain) + difficulty
              IO.puts("Difficulty recalculated! Changed from #{difficulty} to #{new_difficulty}")
              new_difficulty
            else
              difficulty
            end

          case Validator.is_block_valid?(block, chain, difficulty) do
            :ok ->
              Logger.info("Block #{block.index} valid.")
              Blockchain.add_block(chain, block)
            err ->
              Logger.info("Block #{block.index} invalid!")
              chain
          end
        _ ->
          IO.puts "Didnt match"
          chain
      end

    {:noreply, {supervisor, chain}}
  end

  def set_supervisor(pid, supervisor) do
    GenServer.cast(pid, {:set_supervisor, supervisor})
  end
end
