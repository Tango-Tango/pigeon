defmodule Pigeon.Shared do
  @moduledoc false

  def peername(socket) do
    with %{connection: connection} <- :sys.get_state(socket),
         %{config: %{socket: socket2}} <- :sys.get_state(connection),
         %{socket: socket3} <- :sys.get_state(socket2),
         {_, {_, port, _, _}, _} <- socket3 do
      :inet.peername(port)
    else
      _ -> {:error, :unknown}
    end
  end
end
