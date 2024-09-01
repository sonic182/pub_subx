defmodule PubSubxTest do
  use ExUnit.Case
  doctest PubSubx

  setup_all do
    start_supervised!({PubSubx, []})

    :ok
  end

  test "subscribe and publish" do
    PubSubx.subscribe(:whatever, self())
    PubSubx.publish(:whatever, :a_message)

    receive do
      :a_message ->
        :ok
    after
      :timer.seconds(5) ->
        raise "no message received"
    end
  end

  test "unsubscribe" do
    PubSubx.subscribe(:whatever, self())
    PubSubx.unsubscribe(:whatever, self())
    PubSubx.publish(:whatever, :a_message)

    receive do
      :a_message ->
        raise "unsubscribe doesn't work"
    after
      :timer.seconds(1) ->
        :ok
    end
  end

  test "subscribers" do
    PubSubx.subscribe(:foo, self())
    assert PubSubx.subscribers(:foo) == [self()]
  end

  test "topics" do
    PubSubx.subscribe(:foo, self())
    PubSubx.subscribe(:bar, self())
    assert MapSet.new(PubSubx.topics()) == MapSet.new([:foo, :bar])
  end

  test "topics with independent pubsubx" do
    pname = TopicsPubSubx
    start_supervised!({PubSubx, [name: pname]})

    PubSubx.subscribe(:foo, self(), pname)
    PubSubx.subscribe(:bar, self(), pname)
    assert MapSet.new(PubSubx.topics(pname)) == MapSet.new([:foo, :bar])
  end
end
