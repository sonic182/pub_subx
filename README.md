# PubSubx

![Hex.pm Version](https://img.shields.io/hexpm/v/pub_subx)
![License](https://img.shields.io/github/license/sonic182/pub_subx)
![Issues](https://img.shields.io/github/issues/sonic182/pub_subx)

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
    {:pub_subx, "~> 0.2.0"}
  ]
end
```

## Usage

The docs can be found at <https://hexdocs.pm/pub_subx>.


## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
