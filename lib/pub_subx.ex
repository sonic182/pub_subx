defmodule PubSubx do
  @moduledoc """
  `PubSubx` is a lightweight event router for Elixir applications.

  It routes structured events through exact or hierarchical topic subscriptions,
  optional subscriber-side filters, and Telemetry hooks.

  ## API Conventions

  Public functions keep the same argument order:

    - `subscribe(pubsub, topic_pattern, pid, opts \\\\ [])`
    - `publish(pubsub, topic, payload, opts \\\\ [])`
    - `unsubscribe(pubsub, topic_pattern, pid)`

  ## Example

      {:ok, pubsub} = PubSubx.start_link(name: :my_pubsub)
      :ok = PubSubx.subscribe(pubsub, "orders.*", self())
      :ok = PubSubx.publish(pubsub, "orders.created", %{id: 1})

      assert_receive %PubSubx.Event{
        topic: "orders.created",
        payload: %{id: 1}
      }
  """

  use GenServer

  alias PubSubx.Event

  @type topic :: atom | binary
  @type process :: atom | pid
  @type filter_fun :: (Event.t() -> boolean())
  @type publish_opts :: [
          timestamp: DateTime.t(),
          metadata: map(),
          correlation_id: term(),
          trace_id: term()
        ]
  @type subscribe_opts :: [filter: filter_fun()]

  @telemetry_prefix [:pub_subx]

  @typedoc false
  @type subscription :: %{
          pid: pid(),
          topic_pattern: topic(),
          filter: filter_fun() | nil,
          match_type: :exact | :wildcard
        }

  @doc """
  Starts the `PubSubx` server.

  ## Options

    - `:name` - The name to register the `GenServer` under (default: `PubSubx`).
    - `:registry_name` - Backwards-compatible option retained from earlier versions.
    - `:registry_partitions` - Backwards-compatible option retained from earlier versions.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: get_name(opts))
  end

  @impl true
  @spec init(Keyword.t()) :: {:ok, map()}
  def init(opts) do
    name = get_name(opts)
    registry_name = String.to_atom("PubSubx.Registry.#{name}")

    registry_opts = [
      name: Keyword.get(opts, :registry_name, registry_name),
      partitions: Keyword.get(opts, :registry_partitions, System.schedulers_online())
    ]

    state = %{
      exact_subscriptions: %{},
      wildcard_subscriptions: %{},
      subscriber_patterns: %{},
      monitors: %{},
      pubsub: name,
      registry: get_registry(registry_opts)
    }

    {:ok, state}
  end

  @doc """
  Subscribes `pid` to a topic or topic pattern.

  Re-subscribing the same `{pid, topic_pattern}` replaces the subscription options.
  """
  @spec subscribe(process(), topic(), process()) :: :ok
  def subscribe(pubsub, topic_pattern, pid) do
    subscribe(pubsub, topic_pattern, pid, [])
  end

  @doc """
  Subscribes `pid` to a topic or topic pattern with options.

  Supported options:

    - `:filter` - A predicate that receives `%PubSubx.Event{}` and returns `true`
      when the subscriber should receive the event.
  """
  @spec subscribe(process(), topic(), process(), subscribe_opts()) :: :ok
  def subscribe(pubsub, topic_pattern, pid, opts) do
    GenServer.call(pubsub, {:subscribe, topic_pattern, pid, opts})
  end

  @doc """
  Returns the subscribers registered for the exact topic or topic pattern.
  """
  @spec subscribers(process(), topic()) :: [pid()]
  def subscribers(pubsub, topic_pattern) do
    GenServer.call(pubsub, {:subscribers, topic_pattern})
  end

  @doc """
  Lists all active topic keys and wildcard patterns.
  """
  @spec topics(process()) :: [topic()]
  def topics(pubsub) do
    GenServer.call(pubsub, :topics)
  end

  @doc """
  Publishes a payload to the specified topic.
  """
  @spec publish(process(), topic(), term()) :: :ok
  def publish(pubsub, topic, payload) do
    publish(pubsub, topic, payload, [])
  end

  @doc """
  Publishes a payload to the specified topic with envelope options.

  Supported options:

    - `:timestamp`
    - `:metadata`
    - `:correlation_id`
    - `:trace_id`
  """
  @spec publish(process(), topic(), term(), publish_opts()) :: :ok
  def publish(pubsub, topic, payload, opts) do
    GenServer.cast(pubsub, {:publish, topic, payload, opts})
  end

  @doc """
  Unsubscribes `pid` from the specified topic or topic pattern.
  """
  @spec unsubscribe(process(), topic(), process()) :: :ok
  def unsubscribe(pubsub, topic_pattern, pid) do
    GenServer.call(pubsub, {:unsubscribe, topic_pattern, pid})
  end

  @impl true
  @spec handle_cast(term(), map()) :: {:noreply, map()}
  def handle_cast({:publish, topic, payload, opts}, state) do
    event = build_event(topic, payload, opts)
    deliveries = matching_deliveries(state, event)

    Enum.each(deliveries, fn {pid, delivered_event} ->
      send(pid, delivered_event)

      emit_telemetry(
        [:delivery],
        %{count: 1},
        %{
          pubsub: state.pubsub,
          pid: pid,
          topic: delivered_event.topic,
          correlation_id: delivered_event.correlation_id,
          trace_id: delivered_event.trace_id
        }
      )
    end)

    emit_telemetry(
      [:publish],
      %{count: 1},
      %{
        pubsub: state.pubsub,
        topic: event.topic,
        correlation_id: event.correlation_id,
        trace_id: event.trace_id,
        matched_subscribers: map_size(deliveries)
      }
    )

    if map_size(deliveries) == 0 do
      emit_drop(state.pubsub, event, :no_subscribers)
    end

    {:noreply, state}
  end

  @impl true
  @spec handle_call(term(), {pid(), atom()}, map()) :: {:reply, term(), map()}
  def handle_call({:subscribe, topic_pattern, pid, opts}, _from, state) do
    process = get_process(pid)
    subscription = build_subscription(topic_pattern, process, opts)
    state = put_subscription(state, subscription)

    emit_telemetry(
      [:subscribe],
      %{count: 1},
      %{
        pubsub: state.pubsub,
        pid: process,
        topic_pattern: topic_pattern
      }
    )

    emit_subscriber_count(state, topic_pattern)

    {:reply, :ok, state}
  end

  def handle_call({:unsubscribe, topic_pattern, pid}, _from, state) do
    process = get_process(pid)
    {state, removed?} = delete_subscription(state, topic_pattern, process)

    if removed? do
      emit_telemetry(
        [:unsubscribe],
        %{count: 1},
        %{
          pubsub: state.pubsub,
          pid: process,
          topic_pattern: topic_pattern
        }
      )

      emit_subscriber_count(state, topic_pattern)
    end

    {:reply, :ok, state}
  end

  def handle_call(:topics, _from, state) do
    {:reply, get_topics(state), state}
  end

  def handle_call({:subscribers, topic_pattern}, _from, state) do
    subscribers =
      state
      |> subscriptions_for(topic_pattern)
      |> Map.keys()

    {:reply, subscribers, state}
  end

  @impl true
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.get(state.monitors, pid) do
      ^ref ->
        state =
          state
          |> Map.get(:subscriber_patterns)
          |> Map.get(pid, MapSet.new())
          |> Enum.reduce(state, fn topic_pattern, acc ->
            {next_state, _removed?} = delete_subscription(acc, topic_pattern, pid)
            next_state
          end)
          |> remove_monitor(pid)

        {:noreply, state}

      _other ->
        {:noreply, state}
    end
  end

  @doc false
  @spec build_event(topic(), term(), publish_opts()) :: Event.t()
  defp build_event(topic, payload, opts) do
    %Event{
      topic: topic,
      payload: payload,
      timestamp: Keyword.get_lazy(opts, :timestamp, &DateTime.utc_now/0),
      metadata: Keyword.get(opts, :metadata, %{}),
      correlation_id: Keyword.get(opts, :correlation_id),
      trace_id: Keyword.get(opts, :trace_id)
    }
  end

  @doc false
  @spec build_subscription(topic(), pid(), subscribe_opts()) :: subscription()
  defp build_subscription(topic_pattern, pid, opts) do
    filter = Keyword.get(opts, :filter)

    %{
      pid: pid,
      topic_pattern: topic_pattern,
      filter: filter,
      match_type: match_type(topic_pattern)
    }
  end

  @doc false
  @spec matching_deliveries(map(), Event.t()) :: %{pid() => Event.t()}
  defp matching_deliveries(state, event) do
    candidates =
      exact_matches(state, event.topic) ++
        wildcard_matches(state, event.topic)

    Enum.reduce(candidates, %{}, fn subscription, deliveries ->
      evaluate_delivery(deliveries, subscription, event, state.pubsub)
    end)
  end

  @doc false
  @spec exact_matches(map(), topic()) :: [subscription()]
  defp exact_matches(state, topic) do
    state
    |> Map.get(:exact_subscriptions)
    |> Map.get(topic, %{})
    |> Map.values()
  end

  @doc false
  @spec wildcard_matches(map(), topic()) :: [subscription()]
  defp wildcard_matches(state, topic) do
    state
    |> Map.get(:wildcard_subscriptions)
    |> Enum.filter(fn {topic_pattern, _subscriptions} ->
      matches_pattern?(topic_pattern, topic)
    end)
    |> Enum.flat_map(fn {_topic_pattern, subscriptions} ->
      Map.values(subscriptions)
    end)
  end

  @doc false
  @spec evaluate_delivery(%{pid() => Event.t()}, subscription(), Event.t(), atom()) ::
          %{pid() => Event.t()}
  defp evaluate_delivery(deliveries, subscription, event, pubsub) do
    cond do
      Map.has_key?(deliveries, subscription.pid) ->
        deliveries

      filter_matches?(subscription.filter, event) ->
        Map.put(deliveries, subscription.pid, event)

      true ->
        emit_drop(pubsub, event, :filter_rejected)
        deliveries
    end
  end

  @doc false
  @spec filter_matches?(filter_fun() | nil, Event.t()) :: boolean()
  defp filter_matches?(nil, _event), do: true
  defp filter_matches?(filter, event), do: filter.(event)

  @doc false
  @spec matches_pattern?(topic(), topic()) :: boolean()
  defp matches_pattern?(pattern, topic) when is_atom(pattern) or is_atom(topic),
    do: pattern == topic

  defp matches_pattern?(pattern, topic) when is_binary(pattern) and is_binary(topic) do
    case parse_pattern(pattern) do
      {:ok, pattern_segments} ->
        match_segments(pattern_segments, String.split(topic, ".", trim: true))

      :error ->
        false
    end
  end

  @doc false
  @spec parse_pattern(binary()) :: {:ok, [binary()]} | :error
  defp parse_pattern(pattern) do
    segments = String.split(pattern, ".", trim: true)

    cond do
      segments == [] ->
        :error

      Enum.count(segments, &(&1 == "**")) > 1 ->
        :error

      "**" in segments and List.last(segments) != "**" ->
        :error

      true ->
        {:ok, segments}
    end
  end

  @doc false
  @spec match_segments([binary()], [binary()]) :: boolean()
  defp match_segments([], []), do: true
  defp match_segments(["**"], _topic_segments), do: true
  defp match_segments([], _topic_segments), do: false
  defp match_segments(_pattern_segments, []), do: false

  defp match_segments(["*" | pattern_tail], [_ | topic_tail]),
    do: match_segments(pattern_tail, topic_tail)

  defp match_segments([segment | pattern_tail], [segment | topic_tail]),
    do: match_segments(pattern_tail, topic_tail)

  defp match_segments(_pattern_segments, _topic_segments), do: false

  @doc false
  @spec get_topics(map()) :: [topic()]
  defp get_topics(state) do
    Map.keys(state.exact_subscriptions) ++ Map.keys(state.wildcard_subscriptions)
  end

  @doc false
  @spec match_type(topic()) :: :exact | :wildcard
  defp match_type(topic_pattern) when is_atom(topic_pattern), do: :exact

  defp match_type(topic_pattern) when is_binary(topic_pattern) do
    if String.contains?(topic_pattern, "*"), do: :wildcard, else: :exact
  end

  @doc false
  @spec put_subscription(map(), subscription()) :: map()
  defp put_subscription(state, subscription) do
    state
    |> ensure_monitor(subscription.pid)
    |> put_subscription_in_index(subscription)
    |> put_pattern_for_subscriber(subscription.pid, subscription.topic_pattern)
  end

  @doc false
  @spec put_subscription_in_index(map(), subscription()) :: map()
  defp put_subscription_in_index(state, subscription) do
    index_key =
      case subscription.match_type do
        :exact -> :exact_subscriptions
        :wildcard -> :wildcard_subscriptions
      end

    update_in(state, [index_key], fn index ->
      subscriptions = Map.get(index, subscription.topic_pattern, %{})

      Map.put(
        index,
        subscription.topic_pattern,
        Map.put(subscriptions, subscription.pid, subscription)
      )
    end)
  end

  @doc false
  @spec put_pattern_for_subscriber(map(), pid(), topic()) :: map()
  defp put_pattern_for_subscriber(state, pid, topic_pattern) do
    update_in(state, [:subscriber_patterns, pid], fn patterns ->
      patterns
      |> default_set()
      |> MapSet.put(topic_pattern)
    end)
  end

  @doc false
  @spec delete_subscription(map(), topic(), pid()) :: {map(), boolean()}
  defp delete_subscription(state, topic_pattern, pid) do
    case pop_subscription(state, topic_pattern, pid) do
      {nil, state} ->
        {state, false}

      {_subscription, state} ->
        state =
          state
          |> drop_pattern_for_subscriber(pid, topic_pattern)
          |> maybe_remove_monitor(pid)

        {state, true}
    end
  end

  @doc false
  @spec pop_subscription(map(), topic(), pid()) :: {subscription() | nil, map()}
  defp pop_subscription(state, topic_pattern, pid) do
    index_key =
      case match_type(topic_pattern) do
        :exact -> :exact_subscriptions
        :wildcard -> :wildcard_subscriptions
      end

    subscriptions = get_in(state, [Access.key(index_key), Access.key(topic_pattern)]) || %{}
    {subscription, subscriptions} = Map.pop(subscriptions, pid)

    next_state =
      update_in(state, [index_key], fn index ->
        cond do
          subscription == nil ->
            index

          subscriptions == %{} ->
            Map.delete(index, topic_pattern)

          true ->
            Map.put(index, topic_pattern, subscriptions)
        end
      end)

    {subscription, next_state}
  end

  @doc false
  @spec subscriptions_for(map(), topic()) :: %{optional(pid()) => subscription()}
  defp subscriptions_for(state, topic_pattern) do
    case match_type(topic_pattern) do
      :exact -> Map.get(state.exact_subscriptions, topic_pattern, %{})
      :wildcard -> Map.get(state.wildcard_subscriptions, topic_pattern, %{})
    end
  end

  @doc false
  @spec drop_pattern_for_subscriber(map(), pid(), topic()) :: map()
  defp drop_pattern_for_subscriber(state, pid, topic_pattern) do
    update_in(state, [:subscriber_patterns], &drop_from_index(&1, pid, topic_pattern))
  end

  @doc false
  @spec ensure_monitor(map(), pid()) :: map()
  defp ensure_monitor(state, pid) do
    case Map.get(state.monitors, pid) do
      nil ->
        put_in(state.monitors[pid], Process.monitor(pid))

      _ref ->
        state
    end
  end

  @doc false
  @spec maybe_remove_monitor(map(), pid()) :: map()
  defp maybe_remove_monitor(state, pid) do
    case Map.get(state.subscriber_patterns, pid) do
      nil -> remove_monitor(state, pid)
      _patterns -> state
    end
  end

  @doc false
  @spec remove_monitor(map(), pid()) :: map()
  defp remove_monitor(state, pid) do
    case Map.pop(state.monitors, pid) do
      {nil, _monitors} ->
        state

      {ref, monitors} ->
        Process.demonitor(ref, [:flush])
        %{state | monitors: monitors}
    end
  end

  @doc false
  @spec emit_subscriber_count(map(), topic()) :: :ok
  defp emit_subscriber_count(state, topic_pattern) do
    emit_telemetry(
      [:subscriber_count],
      %{subscriber_count: map_size(subscriptions_for(state, topic_pattern))},
      %{
        pubsub: state.pubsub,
        topic_pattern: topic_pattern
      }
    )
  end

  @doc false
  @spec emit_drop(atom(), Event.t(), atom()) :: :ok
  defp emit_drop(pubsub, event, reason) do
    emit_telemetry(
      [:drop],
      %{count: 1},
      %{
        pubsub: pubsub,
        topic: event.topic,
        correlation_id: event.correlation_id,
        trace_id: event.trace_id,
        reason: reason
      }
    )
  end

  @doc false
  @spec emit_telemetry([atom()], map(), map()) :: :ok
  defp emit_telemetry(event_name, measurements, metadata) do
    :telemetry.execute(@telemetry_prefix ++ event_name, measurements, metadata)
  end

  @doc false
  @spec drop_from_index(map(), term(), term()) :: map()
  defp drop_from_index(index, key, value) do
    case Map.get(index, key) do
      nil ->
        index

      entries ->
        entries = MapSet.delete(entries, value)

        if MapSet.size(entries) == 0 do
          Map.delete(index, key)
        else
          Map.put(index, key, entries)
        end
    end
  end

  @doc false
  @spec default_set(MapSet.t() | nil) :: MapSet.t()
  defp default_set(nil), do: MapSet.new()
  defp default_set(set), do: set

  @doc false
  @spec get_process(process()) :: pid()
  defp get_process(pid) when is_atom(pid), do: Process.whereis(pid)
  defp get_process(pid), do: pid

  @doc false
  @spec get_registry(keyword()) :: atom()
  defp get_registry(opts) do
    registry_opts =
      Keyword.merge(
        [
          keys: :duplicate
        ],
        opts
      )

    {:ok, _registry} = Registry.start_link(registry_opts)

    Keyword.get(registry_opts, :name)
  end

  @doc false
  @spec get_name(Keyword.t()) :: atom()
  defp get_name(opts), do: Keyword.get(opts, :name, __MODULE__)
end
