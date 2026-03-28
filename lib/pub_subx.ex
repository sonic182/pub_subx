defmodule PubSubx do
  @moduledoc """
  `PubSubx` is a simple publish-subscribe (PubSub) system built on top of Elixir's `GenServer` and `Registry`.

  The module allows processes to subscribe to topics, publish messages to those topics, and manage subscriptions. It efficiently handles message delivery to subscribed processes and automatically cleans up subscriptions when processes terminate.

  ## Features

  - **Subscribe/Unsubscribe:** Processes can subscribe or unsubscribe from topics.
  - **Publish:** Messages can be published to a topic, and all subscribers to that topic will receive the message.
  - **Dynamic Topics:** Topics are dynamically created as they are subscribed to, and they are removed when no subscribers exist.
  - **Process Monitoring:** Automatically removes subscribers when the process is no longer alive.

  ## Auto module

  `PubSubx.Auto` module is an utility mod that helps developers to use less code for your PubSubx module definition.

  ## Example Usage with Auto mod

  Define an PubSubx module

  ```elixir
  defmodule MyApp.MyPubSub do
    use PubSubx.Auto, name: MyPubSub
  end
  ```

  Include it in your supervisor tree

  ```elixir
  defmodule MyApp.Application do
    use Application

    def start(_type, _args) do
      children = [
        # Start the PubSubx server
        {MyApp.MyPubSub, []}
      ]

      opts = [strategy: :one_for_one, name: MyApp.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end
  ```

  Now you can use the MyPubSub module: 

  ```elixir
  # if you didn't use supervisor tree, you can start it as follow
  {:ok, _pid} = MyApp.MyPubSub.start_link()

  # subscribe a pid (eg: self()) to a topic
  MyApp.MyPubSub.subscribe(:my_topic, self())

  # list subscribers
  subscribers = MyApp.MyPubSub.subscribers(:my_topic)

  # list topics
  topics = MyApp.MyPubSub.topics()

  # publish a message
  MyApp.MyPubSub.publish(:my_topic, "Hello, world!")

  # Unsubscribe a process from a topic
  # This is optional. This happens automatically if the subscribed process dies.
  MyApp.MyPubSub.unsubscribe(:my_topic, self())
  ```

  ## Distributed Publish

  You can check `PubSubx.Utils` for distribute_publish example, when having erlang/elixir nodes interconnected (eg: with libcluster)

  ## Example Usage

  Start the PubSubx server:

      {:ok, pid} = PubSubx.start_link(name: :my_pubsub)

  Subscribe a process to a topic:

      PubSubx.subscribe(:my_topic, self(), :my_pubsub)

  Publish a message to the topic:

      PubSubx.publish(:my_topic, "Hello, subscribers!", :my_pubsub)

  Get the list of subscribers:

      subscribers = PubSubx.subscribers(:my_topic, :my_pubsub)

  Unsubscribe a process from a topic:

      PubSubx.unsubscribe(:my_topic, self(), :my_pubsub)
  """

  use GenServer

  @type topic :: atom | binary
  @type process :: atom | pid

  @doc """
  Starts the `PubSubx` server.

  ## Options

    - `:name` - The name to register the `GenServer` under (default: `PubSubx`).
    - `:registry_name` - Option to possible change the inner registry name.
    - `:registry_partitions` - Option to possible change the inner registry partitions, default: `System.schedulers_online()`
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
      registry: get_registry(registry_opts),
      monitors: %{},
      subscriber_topics: %{},
      topic_subscribers: %{}
    }

    {:ok, state}
  end

  @doc """
  Subscribes a given process (`pid`) to a specific `topic`.
  """
  @spec subscribe(process, topic, process) :: :ok
  def subscribe(pubsub, topic, pid) do
    GenServer.call(pubsub, {:subscribe, {topic, pid}})
  end

  @doc """
  Returns a list of PIDs that are subscribed to the specified `topic`.
  """
  @spec subscribers(process, topic) :: [pid]
  def subscribers(process, topic) do
    GenServer.call(process, {:subscribers, topic})
  end

  @doc """
  Lists all topics that have active subscribers.
  """
  @spec topics(process) :: [topic]
  def topics(process) do
    GenServer.call(process, :topics)
  end

  @doc """
  Publishes a message to the specified `topic`.

  All subscribers to that `topic` will receive the `message`.
  """
  @spec publish(process, topic, term()) :: :ok
  def publish(process, topic, message) do
    GenServer.cast(process, {:publish, {topic, message}})
  end

  @doc """
  Unsubscribes a given process (`pid`) from the specified `topic`.
  """
  @spec unsubscribe(process, topic, process) :: :ok
  def unsubscribe(process, topic, pid) do
    GenServer.call(process, {:unsubscribe, {topic, pid}})
  end

  @impl true
  @spec handle_cast(term(), map()) :: {:noreply, map()}
  def handle_cast({:publish, {topic, message}}, state) do
    state
    |> Map.get(:topic_subscribers)
    |> Map.get(topic, MapSet.new())
    |> Enum.each(&send(&1, message))

    {:noreply, state}
  end

  @impl true
  @spec handle_call(term(), {pid(), atom}, map()) :: {:reply, term(), map()}
  def handle_call({:subscribe, {topic, pid}}, _from, state) do
    process = get_process(pid)

    if subscribed?(state, topic, process) do
      {:reply, :ok, state}
    else
      {:ok, _} = Registry.register(state.registry, topic, target: process)
      {:reply, :ok, subscribe_process(state, topic, process)}
    end
  end

  def handle_call({:unsubscribe, {topic, pid}}, _from, state) do
    process = get_process(pid)

    if subscribed?(state, topic, process) do
      :ok = unregister(state.registry, topic, process)
      {:reply, :ok, unsubscribe_process(state, topic, process)}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call(:topics, _from, state) do
    topics = get_topics(state)
    {:reply, topics, state}
  end

  def handle_call({:subscribers, topic}, _from, state) do
    subscribers =
      state
      |> Map.get(:topic_subscribers)
      |> Map.get(topic, MapSet.new())
      |> Enum.to_list()

    {:reply, subscribers, state}
  end

  @impl true
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.get(state.monitors, pid) do
      ^ref ->
        subscriber_topics = Map.get(state, :subscriber_topics)

        state =
          subscriber_topics
          |> Map.get(pid, MapSet.new())
          |> Enum.reduce(state, fn topic, acc ->
            :ok = unregister(acc.registry, topic, pid)
            drop_subscription(acc, topic, pid)
          end)
          |> remove_monitor(pid)

        {:noreply, state}

      _other ->
        {:noreply, state}
    end
  end

  @doc false
  @spec get_topics(map()) :: [topic]
  defp get_topics(state), do: Map.keys(state.topic_subscribers)

  @doc false
  @spec unregister(atom, topic, pid) :: :ok
  defp unregister(registry, topic, process),
    do: Registry.unregister_match(registry, topic, target: process)

  @doc false
  @spec subscribe_process(map(), topic(), pid()) :: map()
  defp subscribe_process(state, topic, pid) do
    state
    |> ensure_monitor(pid)
    |> put_subscription(topic, pid)
  end

  @doc false
  @spec unsubscribe_process(map(), topic(), pid()) :: map()
  defp unsubscribe_process(state, topic, pid) do
    state
    |> drop_subscription(topic, pid)
    |> maybe_remove_monitor(pid)
  end

  @doc false
  @spec subscribed?(map(), topic(), pid()) :: boolean()
  defp subscribed?(state, topic, pid) do
    state
    |> Map.get(:topic_subscribers)
    |> Map.get(topic, MapSet.new())
    |> MapSet.member?(pid)
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
  @spec put_subscription(map(), topic(), pid()) :: map()
  defp put_subscription(state, topic, pid) do
    state
    |> update_in([:topic_subscribers, topic], fn subscribers ->
      subscribers
      |> default_set()
      |> MapSet.put(pid)
    end)
    |> update_in([:subscriber_topics, pid], fn topics ->
      topics
      |> default_set()
      |> MapSet.put(topic)
    end)
  end

  @doc false
  @spec drop_subscription(map(), topic(), pid()) :: map()
  defp drop_subscription(state, topic, pid) do
    state
    |> update_in([:topic_subscribers], &drop_from_index(&1, topic, pid))
    |> update_in([:subscriber_topics], &drop_from_index(&1, pid, topic))
  end

  @doc false
  @spec maybe_remove_monitor(map(), pid()) :: map()
  defp maybe_remove_monitor(state, pid) do
    case Map.get(state.subscriber_topics, pid) do
      nil -> remove_monitor(state, pid)
      _topics -> state
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
  @spec get_process(process) :: pid
  defp get_process(pid) when is_atom(pid), do: Process.whereis(pid)
  defp get_process(pid), do: pid

  @doc false
  @spec get_registry(keyword()) :: atom
  defp get_registry(opts) do
    registry_opts =
      Keyword.merge(
        [
          keys: :duplicate
        ],
        opts
      )

    {:ok, _registry} =
      Registry.start_link(registry_opts)

    Keyword.get(registry_opts, :name)
  end

  @doc false
  @spec get_name(Keyword.t()) :: atom
  defp get_name(opts), do: Keyword.get(opts, :name, __MODULE__)
end
