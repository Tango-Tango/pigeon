defmodule Pigeon.SocketTracker do
  @moduledoc false
  require Logger

  @ets_peer_table Pigeon.Application.ets_peer_table()

  @doc """
  Check in the ETS table if the given socket (according to its peername) is a duplicate. If
  it is and if `allow_duplicates` is false, then the socket is added to the table and
  `{:error, :duplicate}` is returned. Otherwise the connect response is returned as-is.
  """
  @spec check_duplicate(term(), boolean()) ::
          {:ok, any()} | {:error, :duplicate} | any()
  def check_duplicate(connect_response, allow_duplicates)

  def check_duplicate({:ok, socket}, false) do
    with {:ok, peername} <- Pigeon.Shared.peername(socket),
         dbg(peername),
         true <- :ets.insert_new(@ets_peer_table, {peername}) do
      IO.puts("***** unique")
      {:ok, socket}
    else
      false ->
        IO.puts("***** duplicate")
        Process.unlink(socket)
        Pigeon.Http2.Client.default().close(socket)
        {:error, :duplicate}

      error ->
        Logger.warning(
          "Couldn't get peername for socket. Duplicate check skipped. #{inspect(error)}"
        )

        {:ok, socket}
    end
  end

  def check_duplicate(s, _), do: s
end
