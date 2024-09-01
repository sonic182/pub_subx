defmodule MyPubSubx do
  @moduledoc false

  use PubSubx.Auto,
    name: MyPubSubx
end

defmodule PubSubxMacroTest do
  use ExUnit.Case

  test "subscribe and publish" do
    {:ok, _pid} = start_supervised(MyPubSubx)

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
