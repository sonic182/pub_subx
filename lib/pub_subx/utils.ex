defmodule PubSubx.Utils do
  @moduledoc """
  Provides utility functions for working with PubSub systems in a distributed Elixir environment.

  This module includes functions to facilitate message distribution across nodes in a cluster.
  """

  @doc """
  Distributes a publish message to all nodes in the cluster.

  This function sends a message to the specified `pubsub_mod` on each node that matches the `node_filter`. It uses the `Node.spawn/4` function to execute the `:publish` call on the remote nodes.

  ## Parameters

    - `pubsub_mod`: The module where the `:publish` function is defined. This is typically your PubSub module.
    - `publish_args`: A list of arguments for the `:publish` function. This should include the topic and the message.
    - `node_filter`: A function to filter nodes. It takes a node name as input and returns a boolean indicating whether the node should receive the message. Defaults to accepting all nodes.
    - `node_opts`: Options for node discovery. Defaults to `[:visible, :this]`, which means it will include visible nodes and the current node.

  ## Examples

      iex> PubSubx.Utils.distribute_publish(MyApp.MyPubSub, [:my_topic, "Hello, world!"])
      # This will publish the message "Hello, world!" to the topic `:my_topic` on all nodes in the cluster.

      iex> node_filter = fn node_atom ->
      iex>   node_atom
      iex>   |> Atom.to_string()
      iex>   |> String.contains?("chat")
      iex> end
      iex> PubSubx.Utils.distribute_publish(MyApp.MyPubSub, [:my_topic, "Hello, world!"], &node_filter/1)
      # This will publish the message only to nodes whose name contains "chat".

  """
  @spec distribute_publish(module(), list(), (atom -> boolean()) | nil, list()) :: :ok
  def distribute_publish(
        pubsub_mod,
        publish_args,
        node_filter \\ & &1,
        node_opts \\ [:visible, :this]
      ) do
    node_opts
    |> Node.list()
    |> Stream.filter(node_filter)
    |> Enum.each(&Node.spawn(&1, pubsub_mod, :publish, publish_args))
  end
end
