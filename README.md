# PubSubx

![Hex.pm Version](https://img.shields.io/hexpm/v/pub_subx)
![License](https://img.shields.io/github/license/sonic182/pub_subx)
![Issues](https://img.shields.io/github/issues/sonic182/pub_subx)

`PubSubx` is a lightweight event router for Elixir. It is built for apps that
need more than exact pubsub topics but do not want a larger event bus:
hierarchical topic patterns, subscriber-side filtering, structured event
envelopes, and Telemetry hooks.

## Why use it

- Subscribe with exact topics or wildcard patterns like `"orders.*"` and `"orders.**"`.
- Receive `%PubSubx.Event{}` envelopes with topic, payload, timestamp, metadata,
  correlation ID, and trace ID.
- Filter events at the subscriber so a broad subscription can still be selective.
- Observe subscribe, unsubscribe, publish, delivery, drop, distributed publish,
  and subscriber-count events through Telemetry.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be
installed by adding `pub_subx` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pub_subx, "~> 0.2.0"}
  ]
end
```

## API conventions

The public API keeps the same argument order throughout:

- `subscribe(pubsub, topic_pattern, pid, opts \\ [])`
- `publish(pubsub, topic, payload, opts \\ [])`
- `unsubscribe(pubsub, topic_pattern, pid)`

## Usage

### Add PubSubx to your supervision tree

In your `application.ex`, start the PubSub server as part of your supervision
tree:

```elixir
def start(_type, _args) do
  children = [
    {MyApp.MyPubSub, []}
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### Basic subscribe and publish

Subscriptions are automatically removed when the subscriber process exits, so
explicit `unsubscribe/3` calls are only needed when you want to stop receiving
events before the process terminates.

```elixir
:ok = MyApp.MyPubSub.subscribe("orders.created", self())

:ok = MyApp.MyPubSub.publish("orders.created", %{id: 1},
  metadata: %{source: :checkout},
  correlation_id: "corr-123",
  trace_id: "trace-123"
)

receive do
  %PubSubx.Event{} = event ->
    IO.inspect(event.topic)
    IO.inspect(event.payload)
end
```

### Subscribe with an optional filter

The `:filter` option is optional. Use it only when a subscriber wants to accept
just a subset of the events that match a topic pattern.

As with exact subscriptions, the subscriber is automatically deregistered if
its process exits.

```elixir
:ok =
  MyApp.MyPubSub.subscribe("orders.*", self(),
    filter: fn event -> event.payload.region == :eu end
  )

:ok =
  MyApp.MyPubSub.publish("orders.created", %{id: 1, region: :eu},
    metadata: %{source: :checkout},
    correlation_id: "corr-123",
    trace_id: "trace-123"
  )

receive do
  %PubSubx.Event{} = event ->
    IO.inspect(event.topic)
    IO.inspect(event.payload)
end
```

### Distributed publish across interconnected nodes

If your Erlang nodes are already connected (eg: libcluster usage),
`PubSubx.Utils.distribute_publish/4` can fan a publish out to all nodes or
selected nodes. Local delivery and `node_opts: [:visible, :this]` are enabled
by default; pass `include_local?: false` only when you want remote-only fanout.
This is best-effort delivery; it does not synchronize subscriptions or wait for
acknowledgements.
It also relies on the PubSub `GenServer` being started in each application
supervision tree under the same PubSub module name.

```elixir
:ok = MyApp.MyPubSub.subscribe("orders.created", self())

summary =
  PubSubx.Utils.distribute_publish(MyApp.MyPubSub, "orders.created", %{id: 1},
    publish: [
      metadata: %{source: :cluster},
      correlation_id: "dist-123"
    ]
  )

IO.inspect(summary.attempted_nodes)

# Remote-only fanout:
# PubSubx.Utils.distribute_publish(MyApp.MyPubSub, "orders.created", %{id: 1},
#   include_local?: false
# )

receive do
  %PubSubx.Event{} = event ->
    IO.inspect(event.topic)
    IO.inspect(event.metadata)
end
```

## Topic matching

- Exact atom topics remain exact-only.
- Binary topics can be hierarchical: `"orders.created"`, `"orders.eu.created"`.
- `*` matches one segment.
- `**` matches zero or more trailing segments and must be the last segment.

## Distributed publish

`PubSubx.Utils.distribute_publish/4` provides best-effort cross-node fanout.
It can include the local node, forwards publish options, and emits
`[:pub_subx, :distribute, :publish]`.

It does not:

- synchronize subscriptions across nodes
- wait for acknowledgements
- retry failed remote deliveries

## Telemetry

`PubSubx` emits the following Telemetry events:

- `[:pub_subx, :subscribe]`
- `[:pub_subx, :unsubscribe]`
- `[:pub_subx, :publish]`
- `[:pub_subx, :delivery]`
- `[:pub_subx, :drop]`
- `[:pub_subx, :subscriber_count]`
- `[:pub_subx, :distribute, :publish]`

## Benchmarks

Benchmark scaffolding lives in [`bench/pub_subx_bench.exs`](bench/pub_subx_bench.exs)
and compares:

- `PubSubx` exact publish
- `PubSubx` wildcard publish
- `Phoenix.PubSub` exact publish
- plain `Registry` exact dispatch

Run it with:

```bash
mix run bench/pub_subx_bench.exs
```

The script starts the `phoenix_pubsub` application it needs before running the
comparison, so the command above is the intended way to execute the benchmark.

Example run on a MacBook Pro 13-inch (Mid 2017, no Touch Bar, two Thunderbolt 3
ports), Intel Core i5-7360U 2.30 GHz, 4 cores, 8 GB RAM:

```text
Name                                   ips        average
pub_subx exact publish           1052.15 K        0.95 μs
pub_subx wildcard publish         880.92 K        1.14 μs
phoenix_pubsub exact publish      412.43 K        2.42 μs
registry exact dispatch           360.22 K        2.78 μs
```

Relative to this run:

- `pub_subx exact publish` was `155.11%` faster than `phoenix_pubsub exact publish`
- `pub_subx exact publish` was `192.09%` faster than `registry exact dispatch`
- `pub_subx wildcard publish` was `113.59%` faster than `phoenix_pubsub exact publish`
- `pub_subx wildcard publish` was `144.55%` faster than `registry exact dispatch`
- `pub_subx wildcard publish` was `16.27%` slower than `pub_subx exact publish`

This example is illustrative only. Benchmark results will vary with CPU,
Elixir/Erlang versions, scheduler behavior, and system load.

## Future direction

If repeated event schemas emerge across multiple users of the library, a later
release can add typed event helpers or macros on top of the current event
envelope. That is intentionally deferred for now.

The docs can be found at <https://hexdocs.pm/pub_subx>.

## License

This project is licensed under the MIT License. See
[LICENSE](LICENSE.md) for details.
