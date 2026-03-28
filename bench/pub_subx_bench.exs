Mix.Task.run("app.start")
Application.ensure_all_started(:phoenix_pubsub)

defmodule PubSubxBench.LocalPubSub do
  @moduledoc false

  use PubSubx.Auto, name: __MODULE__
end

defmodule PubSubxBench do
  @moduledoc false

  def run do
    {:ok, _pid} = PubSubxBench.LocalPubSub.start_link()
    {:ok, _phoenix} =
      Supervisor.start_link(
        [{Phoenix.PubSub, name: PubSubxBench.PhoenixPubSub}],
        strategy: :one_for_one
      )

    {:ok, _registry} = Registry.start_link(keys: :duplicate, name: PubSubxBench.Registry)

    PubSubxBench.LocalPubSub.subscribe("orders.created", self())
    PubSubxBench.LocalPubSub.subscribe("orders.*", self())
    Phoenix.PubSub.subscribe(PubSubxBench.PhoenixPubSub, "orders.created")
    Registry.register(PubSubxBench.Registry, "orders.created", [])

    Benchee.run(
      %{
        "pub_subx exact publish" => fn ->
          PubSubxBench.LocalPubSub.publish("orders.created", %{id: 1})
        end,
        "pub_subx wildcard publish" => fn ->
          PubSubxBench.LocalPubSub.publish("orders.created", %{id: 1})
        end,
        "phoenix_pubsub exact publish" => fn ->
          Phoenix.PubSub.broadcast(PubSubxBench.PhoenixPubSub, "orders.created", %{id: 1})
        end,
        "registry exact dispatch" => fn ->
          Registry.dispatch(PubSubxBench.Registry, "orders.created", fn entries ->
            Enum.each(entries, fn {pid, _value} -> send(pid, %{id: 1}) end)
          end)
        end
      },
      time: 2,
      memory_time: 0.5
    )
  end
end

PubSubxBench.run()
