defmodule Pigeon.DispatcherWorker do
  @moduledoc false

  defmodule TimingData do
    @doc """
    Maintain an exponential moving average of response times
    """
    @initial_average_native System.convert_time_unit(100, :millisecond, :native)
    defstruct average_native: @initial_average_native, alpha: 0.2

    @type t :: %__MODULE__{
            average_native: non_neg_integer,
            alpha: float
          }

    @spec update(t(), non_neg_integer()) :: %TimingData{}
    def update(d = %{average_native: avg, alpha: a}, t) do
      %{d | average_native: round(a * t + (1 - a) * avg)}
    end
  end

  use GenServer

  def start_link(opts) do
    opts[:adapter] || raise "adapter is not specified"
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do
    case opts[:adapter].init(opts) do
      {:ok, state} ->
        Pigeon.Registry.register(opts[:supervisor])
        state = Map.put(state, :timing_data, %TimingData{})
        {:ok, %{adapter: opts[:adapter], state: state}}

      {:error, reason} ->
        {:error, reason}

      {:stop, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_info({:"$push", notification}, %{adapter: adapter, state: state}) do
    t0 = :erlang.monotonic_time()

    case adapter.handle_push(notification, state) do
      {:noreply, new_state} ->
        new_state = update_timing_data(new_state, t0)
        {:noreply, %{adapter: adapter, state: new_state}}

      {:stop, reason, new_state} ->
        {:stop, reason, %{adapter: adapter, state: new_state}}
    end
  end

  def handle_info(msg, %{adapter: adapter, state: state}) do
    case adapter.handle_info(msg, state) do
      {:noreply, new_state} ->
        {:noreply, %{adapter: adapter, state: new_state}}

      {:stop, reason, new_state} ->
        {:stop, reason, %{adapter: adapter, state: new_state}}
    end
  end

  @impl GenServer
  def handle_call(:info, _from, %{adapter: adapter, state: state}) do
    average_response_time_ms =
      System.convert_time_unit(
        state.timing_data.average_native,
        :native,
        :millisecond
      )

    info = %{
      peername: peername(state),
      average_response_time_ms: average_response_time_ms
    }

    {:reply, info, %{adapter: adapter, state: state}}
  end

  defp peername(state) do
    with %{socket: socket} <- state,
         %{connection: connection} <- :sys.get_state(socket),
         %{config: %{socket: socket2}} <- :sys.get_state(connection),
         %{socket: socket3} <- :sys.get_state(socket2),
         {_, {_, port, _, _}, _} <- socket3,
         {:ok, addr} <- :inet.peername(port) do
      addr
    else
      _ -> "unknown"
    end
  end

  defp update_timing_data(state, t0) do
    Map.update!(
      state,
      :timing_data,
      &TimingData.update(&1, :erlang.monotonic_time() - t0)
    )
  end
end
