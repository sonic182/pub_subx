# PubSubx

`PubSubx` is a lightweight and flexible publish-subscribe (PubSub) library built on top of Elixir's `GenServer` and `Registry`. It allows processes to communicate by subscribing to topics and receiving messages when they are published. This is useful for decoupling components in your Elixir applications, enabling easier scalability and maintainability.

## Features

- **Subscribe/Unsubscribe**: Processes can easily subscribe or unsubscribe from topics.
- **Publish**: Messages can be published to any topic, notifying all subscribed processes.
- **Dynamic Topic Management**: Topics are created and removed dynamically based on subscriptions.
- **Process Monitoring**: Automatically handles the removal of subscriptions when processes terminate.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed by adding `pub_subx` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pub_subx, "~> 0.1.1"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc) and published on [HexDocs](https://hexdocs.pm). Once published, the docs can be found at <https://hexdocs.pm/pub_subx>.