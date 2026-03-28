defmodule MyPubSubx do
  @moduledoc false

  use PubSubx.Auto,
    name: MyPubSubx
end

defmodule PubSubxMacroTest do
  use ExUnit.Case

  alias PubSubx.Event

  test "auto wrapper forwards subscribe and publish options" do
    {:ok, _pid} = start_supervised(MyPubSubx)

    :ok =
      MyPubSubx.subscribe("orders.*", self(), filter: fn event -> event.payload.region == :eu end)

    :ok =
      MyPubSubx.publish("orders.created", %{region: :eu},
        metadata: %{source: :macro},
        correlation_id: "macro-corr"
      )

    assert_receive %Event{
      topic: "orders.created",
      payload: %{region: :eu},
      metadata: %{source: :macro},
      correlation_id: "macro-corr"
    }
  end
end
