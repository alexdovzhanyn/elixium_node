defmodule ElixiumNode do
  use GenServer

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
    case msg do
      t ->
        IO.inspect t
    end

    {:noreply, {supervisor, chain}}
  end

  def set_supervisor(pid, supervisor) do
    GenServer.cast(pid, {:set_supervisor, supervisor})
  end
end
