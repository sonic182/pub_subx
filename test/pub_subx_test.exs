defmodule PubSubxTest do
  use ExUnit.Case
  doctest PubSubx

  setup_all do
    {:ok, pubsub} = start_supervised({PubSubx, []})

    %{pubsub: pubsub}
  end

  test "subscribe and publish", %{pubsub: pubsub} do
    PubSubx.subscribe(pubsub, :whatever, self())
    PubSubx.publish(pubsub, :whatever, :a_message)

    receive do
      :a_message ->
        :ok
    after
      :timer.seconds(5) ->
        raise "no message received"
    end
  end

  test "unsubscribe", %{pubsub: pubsub} do
    PubSubx.subscribe(pubsub, :whatever, self())
    PubSubx.unsubscribe(pubsub, :whatever, self())
    PubSubx.publish(pubsub, :whatever, :a_message)

    receive do
      :a_message ->
        raise "unsubscribe doesn't work"
    after
      :timer.seconds(1) ->
        :ok
    end
  end

  test "subscribers", %{pubsub: pubsub} do
    PubSubx.subscribe(pubsub, :foo, self())
    assert PubSubx.subscribers(pubsub, :foo) == [self()]
  end

  test "topics", %{pubsub: pubsub} do
    PubSubx.subscribe(pubsub, :foo, self())
    PubSubx.subscribe(pubsub, :bar, self())
    assert MapSet.new(PubSubx.topics(pubsub)) == MapSet.new([:foo, :bar])
  end

  test "topics with independent pubsubx" do
    pname = TopicsPubSubx
    start_supervised!({PubSubx, [name: pname]})

    PubSubx.subscribe(pname, :foo, self())
    PubSubx.subscribe(pname, :bar, self())
    assert MapSet.new(PubSubx.topics(pname)) == MapSet.new([:foo, :bar])
  end
end
