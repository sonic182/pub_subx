defmodule PubSubx.Utils do
  @moduledoc """
  Best-effort utilities for working with `PubSubx` across connected Erlang nodes.

  `PubSubx.Utils.distribute_publish/4` fans a publish call out to visible nodes
  and includes the local node by default. Pass `include_local?: false` to
  suppress local delivery. It does not synchronize subscriptions across nodes,
  wait for acknowledgements, or retry failed deliveries.
  """

  @type distribute_opts :: [
          publish: keyword(),
          node_filter: (node() -> boolean()),
          node_opts: [node_type()],
          include_local?: boolean()
        ]

  @type node_type :: :visible | :hidden | :connected | :this

  @doc """
  Publishes an event locally and/or across connected nodes with best-effort fanout.

  ## Options

    - `:publish` - Keyword options forwarded to `PubSubx.publish/4`.
    - `:node_filter` - Predicate for selecting nodes.
    - `:node_opts` - Options passed to `Node.list/1`.
      Defaults to `[:visible, :this]`.
    - `:include_local?` - Whether to publish to the current node as part of the fanout.
      Defaults to `true`.

  ## Returns

  A summary map describing the attempted fanout:

      %{
        attempted_nodes: [node()],
        local?: boolean(),
        remote_count: non_neg_integer()
      }
  """
  @spec distribute_publish(PubSubx.process(), PubSubx.topic(), term(), distribute_opts()) :: %{
          attempted_nodes: [node()],
          local?: boolean(),
          remote_count: non_neg_integer()
        }
  def distribute_publish(pubsub, topic, payload, opts \\ []) do
    publish_opts = Keyword.get(opts, :publish, [])
    node_filter = Keyword.get(opts, :node_filter, fn _node -> true end)
    node_opts = Keyword.get(opts, :node_opts, [:visible, :this])
    include_local? = Keyword.get(opts, :include_local?, true)

    current_node = node()

    selected_nodes =
      node_opts
      |> Node.list()
      |> Enum.filter(node_filter)

    remote_nodes = Enum.reject(selected_nodes, &(&1 == current_node))

    if include_local? do
      PubSubx.publish(pubsub, topic, payload, publish_opts)
    end

    Enum.each(remote_nodes, fn remote_node ->
      Node.spawn(remote_node, PubSubx, :publish, [pubsub, topic, payload, publish_opts])
    end)

    attempted_nodes =
      remote_nodes ++
        if include_local?, do: [current_node], else: []

    summary = %{
      attempted_nodes: attempted_nodes,
      local?: include_local?,
      remote_count: length(remote_nodes)
    }

    :telemetry.execute(
      [:pub_subx, :distribute, :publish],
      %{attempted_count: length(attempted_nodes), remote_count: length(remote_nodes)},
      %{
        pubsub: pubsub,
        topic: topic,
        attempted_nodes: attempted_nodes,
        local?: summary.local?
      }
    )

    summary
  end
end
