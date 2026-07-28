defmodule Pigeon.Pushy.Config do
  @moduledoc false

  defstruct key: nil,
            port: 443,
            uri: nil

  @typedoc ~S"""
  Pushy configuration struct

  This struct should not be set directly. Instead, use `new/1`
  with `t:config_opts/0`.

  ## Examples

      %Pigeon.Pushy.Config{
        key: "some-secret-key",
        uri: "api.pushy.me",
        port: 443
      }
  """
  @type t :: %__MODULE__{
          key: binary | nil,
          uri: binary | nil,
          port: pos_integer
        }

  @typedoc ~S"""
  Options for configuring Pushy connections.

  ## Configuration Options
  - `:key` - Pushy secrety key.
  - `:uri` - Pushy server uri.
  - `:port` - Push server port. Can be any value, but Pushy only accepts
    `443`
  """
  @type config_opts :: [
          key: binary,
          uri: binary,
          port: pos_integer
        ]

  @doc false
  def default_name, do: :pushy_default

  @doc ~S"""
  Returns a new `Pushy.Config` with given `opts`.

  ## Examples

      iex> Pigeon.Pushy.Config.new(
      ...>   key: System.get_env("PUSHY_SECRET_KEY"),
      ...>   uri: "api.pushy.me",
      ...>   port: 443
      ...> )
      %Pigeon.Pushy.Config{
        key: System.get_env("PUSHY_SECRET_KEY"),
        port: 443,
        uri: "api.pushy.me"
      }
  """
  def new(opts) when is_list(opts) do
    %__MODULE__{
      key: opts |> Keyword.get(:key),
      uri: Keyword.get(opts, :uri, "api.pushy.me"),
      port: Keyword.get(opts, :port, 443)
    }
  end

  @doc ~S"""
  Returns whether a given config has valid credentials.

  ## Examples

      iex> [] |> new() |> valid?()
      false
  """
  def valid?(config) do
    valid_item?(config.uri) and valid_item?(config.key)
  end

  defp valid_item?(item), do: is_binary(item) and String.length(item) > 0

  @spec validate!(any) :: :ok | no_return
  def validate!(config) do
    Pigeon.Configurable.validate!(config)
  end
end

defimpl Pigeon.Configurable, for: Pigeon.Pushy.Config do
  @moduledoc false

  require Logger

  alias Pigeon.Encodable
  alias Pigeon.Pushy.{Config}

  @type sock :: {:sslsocket, any, pid | {any, any}}

  # Configurable Callbacks

  @spec connect(any) :: {:ok, sock} | {:error, String.t()}
  def connect(_) do
    {:error, "Not supported. pushy uses an HTTP1 adapter"}
  end

  def push_headers(%Config{}, _notification, _opts) do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
  end

  def push_payload(_config, notification, _opts) do
    Encodable.binary_payload(notification)
  end

  def handle_end_stream(_config, _stream, _notif) do
    {:error, "Not supported. pushy uses an HTTP1 adapter"}
  end

  def schedule_ping(_config), do: :ok

  def close(_config), do: nil

  @spec validate!(any) :: :ok | no_return
  def validate!(config) do
    if !valid_item?(config.uri) or !valid_item?(config.key) do
      raise Pigeon.ConfigError,
        reason: "attempted to start without valid key or uri",
        config: redact(config)
    end

    :ok
  end

  defp valid_item?(item), do: is_binary(item) and String.length(item) > 0

  defp redact(config) do
    [:key]
    |> Enum.reduce(config, fn k, acc ->
      case Map.get(acc, k) do
        nil -> acc
        _ -> Map.put(acc, k, "[FILTERED]")
      end
    end)
  end
end
