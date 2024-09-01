defmodule MyPubSubx do
  @moduledoc false

  use PubSubx.Auto,
    name: MyPubSubx
end

defmodule PubSubxMacroTest do
  use ExUnit.Case

  test "start with supervisor" do
    children = [
      MyPubSubx
    ]

    {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)
    assert is_pid(pid)
  end

  test "subscribe and publish" do
    {:ok, _pid} = MyPubSubx.start_link()

    MyPubSubx.subscribe(:whatever, self())
    MyPubSubx.publish(:whatever, :a_message)

    receive do
      :a_message ->
        :ok
    after
      :timer.seconds(5) ->
        raise "no message received"
    end
  end
end
