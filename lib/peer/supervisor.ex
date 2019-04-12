defmodule ElixiumNode.PeerRouter.Supervisor do
  use Supervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    children = [
      {Pico.Client.Supervisor, {ElixiumNode.PeerRouter}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
