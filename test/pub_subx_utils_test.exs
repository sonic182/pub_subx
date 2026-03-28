defmodule PubSubx.UtilsTest do
  use ExUnit.Case

  alias PubSubx.Event
  alias PubSubx.Utils

  setup do
    pubsub_name = :"distributed_#{System.unique_integer([:positive])}"
    {:ok, pubsub} = start_supervised({PubSubx, [name: pubsub_name]})

    %{pubsub: pubsub}
  end

  test "distribute_publish includes the local node by default and forwards publish opts", %{
    pubsub: pubsub
  } do
    :ok = PubSubx.subscribe(pubsub, "orders.created", self())
    test_pid = self()

    :ok =
      :telemetry.attach(
        {__MODULE__, :distribute_publish, test_pid},
        [:pub_subx, :distribute, :publish],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event_name, measurements, metadata})
        end,
        nil
      )

    summary =
      Utils.distribute_publish(pubsub, "orders.created", %{id: 1},
        publish: [metadata: %{source: :distributed}, correlation_id: "dist-1"]
      )

    assert summary.local?
    assert summary.remote_count == 0
    assert summary.attempted_nodes == [node()]

    assert_receive %Event{
      topic: "orders.created",
      payload: %{id: 1},
      metadata: %{source: :distributed},
      correlation_id: "dist-1"
    }

    assert_receive {:telemetry, [:pub_subx, :distribute, :publish],
                    %{attempted_count: 1, remote_count: 0},
                    %{attempted_nodes: [current_node], local?: true}}

    assert current_node == node()
  after
    :telemetry.detach({__MODULE__, :distribute_publish, self()})
  end

  test "distribute_publish keeps local delivery even when remote filters reject nodes", %{
    pubsub: pubsub
  } do
    summary =
      Utils.distribute_publish(pubsub, "orders.created", %{id: 1},
        node_filter: fn _node -> false end
      )

    assert summary == %{attempted_nodes: [node()], local?: true, remote_count: 0}
  end

  test "distribute_publish can opt out of local delivery", %{pubsub: pubsub} do
    :ok = PubSubx.subscribe(pubsub, "orders.created", self())

    summary =
      Utils.distribute_publish(pubsub, "orders.created", %{id: 1}, include_local?: false)

    assert summary == %{attempted_nodes: [], local?: false, remote_count: 0}
    refute_receive %Event{}
  end
end
