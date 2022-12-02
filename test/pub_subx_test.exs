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
    start_link_supervised!({PubSubx, [name: TopicsPubSubx]})

    PubSubx.subscribe(:foo, self(), TopicsPubSubx)
    PubSubx.subscribe(:bar, self(), TopicsPubSubx)
    assert MapSet.new(PubSubx.topics(TopicsPubSubx)) == MapSet.new([:foo, :bar])
  end
end
