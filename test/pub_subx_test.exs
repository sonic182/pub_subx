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
    assert MapSet.new(PubSubx.subscribers(pubsub, :foo)) == MapSet.new([self()])
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

  test "duplicate subscribe is idempotent", %{pubsub: pubsub} do
    PubSubx.subscribe(pubsub, :foo, self())
    PubSubx.subscribe(pubsub, :foo, self())
    PubSubx.publish(pubsub, :foo, :only_once)

    assert_receive :only_once
    refute_receive :only_once
    assert MapSet.new(PubSubx.subscribers(pubsub, :foo)) == MapSet.new([self()])
  end

  test "topics include subscriptions from other processes", %{pubsub: pubsub} do
    pid =
      spawn(fn ->
        PubSubx.subscribe(pubsub, :other_topic, self())

        receive do
          :stop -> :ok
        end
      end)

    assert eventually(fn ->
             MapSet.member?(MapSet.new(PubSubx.topics(pubsub)), :other_topic)
           end)

    send(pid, :stop)
  end

  test "dead subscribers are cleaned up", %{pubsub: pubsub} do
    pid =
      spawn(fn ->
        PubSubx.subscribe(pubsub, :ephemeral, self())

        receive do
          :stop -> :ok
        end
      end)

    assert eventually(fn ->
             PubSubx.subscribers(pubsub, :ephemeral) != []
           end)

    send(pid, :stop)

    assert eventually(fn ->
             PubSubx.subscribers(pubsub, :ephemeral) == [] and
               :ephemeral not in PubSubx.topics(pubsub)
           end)
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
end
