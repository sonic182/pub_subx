defmodule PubSubxTest do
  use ExUnit.Case

  alias PubSubx.Event

  doctest PubSubx

  setup do
    pubsub_name = :"pubsub_#{System.unique_integer([:positive])}"
    {:ok, pubsub} = start_supervised({PubSubx, [name: pubsub_name]})

    %{pubsub: pubsub}
  end

  test "publish/3 delivers an event envelope", %{pubsub: pubsub} do
    :ok = PubSubx.subscribe(pubsub, "orders.created", self())
    :ok = PubSubx.publish(pubsub, "orders.created", %{id: 1})

    assert_receive %Event{
      topic: "orders.created",
      payload: %{id: 1},
      timestamp: %DateTime{},
      metadata: %{},
      correlation_id: nil,
      trace_id: nil
    }
  end

  test "publish/4 includes metadata and ids", %{pubsub: pubsub} do
    timestamp = DateTime.utc_now()
    :ok = PubSubx.subscribe(pubsub, "orders.created", self())

    :ok =
      PubSubx.publish(pubsub, "orders.created", %{id: 1},
        timestamp: timestamp,
        metadata: %{source: :test},
        correlation_id: "corr-1",
        trace_id: "trace-1"
      )

    assert_receive %Event{
      topic: "orders.created",
      payload: %{id: 1},
      timestamp: ^timestamp,
      metadata: %{source: :test},
      correlation_id: "corr-1",
      trace_id: "trace-1"
    }
  end

  test "wildcard subscriptions match hierarchical topics", %{pubsub: pubsub} do
    :ok = PubSubx.subscribe(pubsub, "orders.*", self())
    :ok = PubSubx.publish(pubsub, "orders.created", %{id: 1})

    assert_receive %Event{topic: "orders.created"}
  end

  test "double-star subscriptions match trailing segments", %{pubsub: pubsub} do
    :ok = PubSubx.subscribe(pubsub, "orders.**", self())
    :ok = PubSubx.publish(pubsub, "orders.eu.created", %{id: 1})

    assert_receive %Event{topic: "orders.eu.created"}
  end

  test "atom topics remain exact matches", %{pubsub: pubsub} do
    :ok = PubSubx.subscribe(pubsub, :orders, self())
    :ok = PubSubx.publish(pubsub, :orders, %{id: 1})
    :ok = PubSubx.publish(pubsub, :"orders.*", %{id: 2})

    assert_receive %Event{topic: :orders, payload: %{id: 1}}
    refute_receive %Event{topic: :"orders.*"}
  end

  test "filter can reject deliveries", %{pubsub: pubsub} do
    :ok =
      PubSubx.subscribe(pubsub, "orders.*", self(),
        filter: fn event -> event.payload.region == :eu end
      )

    :ok = PubSubx.publish(pubsub, "orders.created", %{region: :us})
    refute_receive %Event{}
  end

  test "re-subscribing replaces the filter", %{pubsub: pubsub} do
    :ok =
      PubSubx.subscribe(pubsub, "orders.*", self(),
        filter: fn event -> event.payload.region == :eu end
      )

    :ok =
      PubSubx.subscribe(pubsub, "orders.*", self(),
        filter: fn event -> event.payload.region == :us end
      )

    :ok = PubSubx.publish(pubsub, "orders.created", %{region: :us})

    assert_receive %Event{payload: %{region: :us}}
  end

  test "one pid receives one delivery even if exact and wildcard subscriptions match", %{
    pubsub: pubsub
  } do
    :ok = PubSubx.subscribe(pubsub, "orders.created", self())
    :ok = PubSubx.subscribe(pubsub, "orders.*", self())
    :ok = PubSubx.publish(pubsub, "orders.created", %{id: 1})

    assert_receive %Event{topic: "orders.created"}
    refute_receive %Event{}
  end

  test "subscribers and topics reflect exact and wildcard registrations", %{pubsub: pubsub} do
    :ok = PubSubx.subscribe(pubsub, "orders.*", self())
    :ok = PubSubx.subscribe(pubsub, :system, self())

    assert MapSet.new(PubSubx.subscribers(pubsub, "orders.*")) == MapSet.new([self()])
    assert MapSet.new(PubSubx.topics(pubsub)) == MapSet.new(["orders.*", :system])
  end

  test "dead subscribers are cleaned up", %{pubsub: pubsub} do
    pid =
      spawn(fn ->
        :ok = PubSubx.subscribe(pubsub, "orders.**", self())

        receive do
          :stop -> :ok
        end
      end)

    assert eventually(fn ->
             PubSubx.subscribers(pubsub, "orders.**") != []
           end)

    send(pid, :stop)

    assert eventually(fn ->
             PubSubx.subscribers(pubsub, "orders.**") == [] and
               "orders.**" not in PubSubx.topics(pubsub)
           end)
  end

  test "telemetry emits subscribe, publish, delivery, drop, unsubscribe, and subscriber_count", %{
    pubsub: pubsub
  } do
    test_pid = self()

    attach_many(
      [
        [:pub_subx, :subscribe],
        [:pub_subx, :publish],
        [:pub_subx, :delivery],
        [:pub_subx, :drop],
        [:pub_subx, :unsubscribe],
        [:pub_subx, :subscriber_count]
      ],
      fn event_name, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event_name, measurements, metadata})
      end
    )

    :ok =
      PubSubx.subscribe(pubsub, "orders.*", self(),
        filter: fn event -> event.payload.region == :eu end
      )

    assert_receive {:telemetry, [:pub_subx, :subscribe], %{count: 1},
                    %{topic_pattern: "orders.*"}}

    assert_receive {:telemetry, [:pub_subx, :subscriber_count], %{subscriber_count: 1}, _metadata}

    :ok = PubSubx.publish(pubsub, "orders.created", %{region: :us})

    assert_receive {:telemetry, [:pub_subx, :drop], %{count: 1}, %{reason: :filter_rejected}}

    assert_receive {:telemetry, [:pub_subx, :publish], %{count: 1}, %{matched_subscribers: 0}}

    :ok = PubSubx.publish(pubsub, "orders.created", %{region: :eu})

    assert_receive {:telemetry, [:pub_subx, :delivery], %{count: 1}, %{topic: "orders.created"}}

    assert_receive {:telemetry, [:pub_subx, :publish], %{count: 1}, %{matched_subscribers: 1}}

    :ok = PubSubx.unsubscribe(pubsub, "orders.*", self())

    assert_receive {:telemetry, [:pub_subx, :unsubscribe], %{count: 1},
                    %{topic_pattern: "orders.*"}}

    assert_receive {:telemetry, [:pub_subx, :subscriber_count], %{subscriber_count: 0}, _metadata}
  after
    detach_many()
  end

  defp eventually(fun, attempts \\ 20)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  defp attach_many(events, handler) do
    Enum.each(events, fn event ->
      :ok = :telemetry.attach(handler_id(event), event, handler, nil)
    end)
  end

  defp detach_many do
    for event <- [
          [:pub_subx, :subscribe],
          [:pub_subx, :publish],
          [:pub_subx, :delivery],
          [:pub_subx, :drop],
          [:pub_subx, :unsubscribe],
          [:pub_subx, :subscriber_count]
        ] do
      :telemetry.detach(handler_id(event))
    end
  end

  defp handler_id(event), do: {__MODULE__, event, self()}
end
