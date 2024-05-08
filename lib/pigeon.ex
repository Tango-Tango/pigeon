defmodule Pigeon do
  @moduledoc """
  HTTP2-compliant wrapper for sending iOS and Android push notifications.

  ## Getting Started

  Check the module documentation for your push notification service.

    - `Pigeon.ADM` - Amazon Android.
    - `Pigeon.APNS` - Apple iOS.
    - `Pigeon.FCM` - Firebase Cloud Messaging v1 API.
    - `Pigeon.LegacyFCM` - Firebase Cloud Messaging Legacy API.

  ## Creating Dynamic Runtime Dispatchers

  Pigeon can spin up dynamic dispatchers for a variety of advanced use-cases, such as
  supporting dozens of dispatcher configurations or custom connection pools.

  See `Pigeon.Dispatcher` for instructions.

  ## Writing a Custom Dispatcher Adapter

  Want to write a Pigeon adapter for an unsupported push notification service?

  See `Pigeon.Adapter` for instructions.
  """

  alias Pigeon.Tasks

  @default_timeout 5_000

  @typedoc ~S"""
  Async callback for push notifications response.

  ## Examples

      handler = fn(%Pigeon.ADM.Notification{response: response}) ->
        case response do
          :success ->
            Logger.debug "Push successful!"
          :unregistered ->
            Logger.error "Bad device token!"
          _error ->
            Logger.error "Some other error happened."
        end
      end

      n = Pigeon.ADM.Notification.new("token", %{"message" => "test"})
      Pigeon.ADM.push(n, on_response: handler)
  """
  @type on_response ::
          (notification -> no_return)
          | {module, atom}
          | {module, atom, [any]}

  @type notification :: %{
          :__struct__ => atom(),
          :__meta__ => Pigeon.Metadata.t(),
          optional(atom()) => any()
        }

  @typedoc ~S"""
  Options for sending push notifications.

  - `:on_response` - Optional async callback triggered on receipt of push.
    See `t:on_response/0`
  - `:timeout` - Push timeout. Defaults to 5000ms.
  """
  @type push_opts :: [
          on_response: on_response | nil,
          timeout: non_neg_integer
        ]

  @doc """
  Returns the configured default pool size for Pigeon dispatchers.
  To customize this value, include the following in your config/config.exs:

      config :pigeon, :default_pool_size, 5
  """
  @spec default_pool_size :: pos_integer
  def default_pool_size() do
    Application.get_env(:pigeon, :default_pool_size, 5)
  end

  @doc """
  Returns the configured JSON encoding library for Pigeon.
  To customize the JSON library, include the following in your config/config.exs:

      config :pigeon, :json_library, Jason
  """
  @spec json_library :: module
  def json_library do
    Application.get_env(:pigeon, :json_library, Jason)
  end

  @spec push(pid | atom, notification :: notification, push_opts) ::
          notification :: struct | no_return
  @spec push(pid | atom, notifications :: [notification, ...], push_opts) ::
          notifications :: [struct, ...] | no_return
  def push(pid, notifications, opts \\ [])

  def push(pid, notifications, opts) when is_list(notifications) do
    for n <- notifications, do: push(pid, n, opts)
  end

  def push(pid, notification, opts) do
    if Keyword.has_key?(opts, :on_response) do
      on_response = Keyword.get(opts, :on_response)
      notification = put_on_response(notification, on_response)
      push_async(pid, notification)
    else
      timeout = Keyword.get(opts, :timeout, @default_timeout)
      push_sync(pid, notification, timeout)
    end
  end

  defp push_sync(pid, notification, timeout) do
    myself = self()
    ref = :erlang.make_ref()
    on_response = fn x -> send(myself, {:"$push", ref, x}) end
    notification = put_on_response(notification, on_response)
    t0 = :erlang.monotonic_time()
    start_response = push_async(pid, notification)
    worker_pid = get_worker_pid(start_response)
    worker_info = GenServer.call(worker_pid, :info)
    timeout = calculate_timeout(timeout, worker_info)

    receive do
      {:"$push", ^ref, x} ->
        rtt = :erlang.monotonic_time() - t0
        GenServer.call(worker_pid, {:update_timing_data, rtt})
        rtt_ms = System.convert_time_unit(rtt, :native, :millisecond)
        Map.merge(x, %{worker_info: worker_info, response_time_ms: rtt_ms})
    after
      timeout ->
        Map.merge(notification, %{
          response: :timeout,
          worker_info: worker_info,
          response_time_ms: timeout
        })
    end
  end

  @spec push_async(pid(), notification) ::
          :ok | DynamicSupervisor.on_start_child()
  defp push_async(pid, notification) do
    case Pigeon.Registry.next(pid) do
      nil ->
        Tasks.process_on_response(%{notification | response: :not_started})

      pid ->
        send(pid, {:"$push", notification})
        {:ok, pid}
    end
  end

  defp put_on_response(notification, on_response) do
    meta = %{notification.__meta__ | on_response: on_response}
    %{notification | __meta__: meta}
  end

  defp get_worker_pid({:ok, pid}), do: pid
  defp get_worker_pid({:ok, pid, _}), do: pid
  defp get_worker_pid({:error, {:already_started, pid}}), do: pid
  defp get_worker_pid(_), do: nil

  defp calculate_timeout(timeout, worker_info) do
    if timeout == :dynamic do
      worker_info.average_response_time_ms * 2
    else
      timeout
    end
  end
end
