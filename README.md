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
- Observe subscribe, unsubscribe, publish, delivery, drop, and subscriber-count
  events through Telemetry.

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

## Usage

```elixir
{:ok, pubsub} = PubSubx.start_link(name: :my_pubsub)

PubSubx.subscribe(:my_pubsub, "orders.*", self(),
  filter: fn event -> event.payload.region == :eu end
)

PubSubx.publish(:my_pubsub, "orders.created", %{id: 1, region: :eu},
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

## Topic matching

- Exact atom topics remain exact-only.
- Binary topics can be hierarchical: `"orders.created"`, `"orders.eu.created"`.
- `*` matches one segment.
- `**` matches zero or more trailing segments and must be the last segment.

## Telemetry

`PubSubx` emits the following Telemetry events:

- `[:pub_subx, :subscribe]`
- `[:pub_subx, :unsubscribe]`
- `[:pub_subx, :publish]`
- `[:pub_subx, :delivery]`
- `[:pub_subx, :drop]`
- `[:pub_subx, :subscriber_count]`

The docs can be found at <https://hexdocs.pm/pub_subx>.

## License

This project is licensed under the MIT License. See
[LICENSE](LICENSE.md) for details.
