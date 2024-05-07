defmodule Pigeon.Pushy.ResultParser do
  @moduledoc false
  alias Pigeon.Pushy.Error

  def parse(
        notification,
        %{
          "id" => push_id,
          "success" => success_status,
          "info" => %{"devices" => num_devices}
        } = response
      ) do
    notification =
      notification
      |> Map.put(:push_id, push_id)
      |> Map.put(:success, success_status)
      |> Map.put(:successful_device_count, num_devices)
      |> Map.put(:response, if(success_status, do: :success, else: :failure))

    if match?(%{"info" => %{"failed" => _}}, response) do
      notification
      |> Map.put(:failed, response["info"]["failed"])
    else
      notification
    end
  end

  def parse(notification, %{"code" => _} = response) do
    Error.parse(notification, response)
  end
end
