defmodule Pigeon.Application do
  @moduledoc false

  use Application
  alias Pigeon.APNS
  alias Pigeon.Http2.Client

  @ets_peer_table :ets_peer_table
  def ets_peer_table, do: @ets_peer_table

  @doc false
  def start(_type, _args) do
    Client.default().start

    children = [
      Pigeon.Registry,
      {APNS.Token, %{}},
      {Task.Supervisor, name: Pigeon.Tasks}
    ]

    :ets.new(@ets_peer_table, [:set, :public, :named_table])

    opts = [strategy: :one_for_one, name: :pigeon]
    Supervisor.start_link(children, opts)
  end
end
