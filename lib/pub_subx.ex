defmodule PubSubx do
  @moduledoc """
  `PubSubx` is a simple publish-subscribe (PubSub) system built on top of Elixir's `GenServer` and `Registry`.

  The module allows processes to subscribe to topics, publish messages to those topics, and manage subscriptions. It efficiently handles message delivery to subscribed processes and automatically cleans up subscriptions when processes terminate.

  ## Features

  - **Subscribe/Unsubscribe:** Processes can subscribe or unsubscribe from topics.
  - **Publish:** Messages can be published to a topic, and all subscribers to that topic will receive the message.
  - **Dynamic Topics:** Topics are dynamically created as they are subscribed to, and they are removed when no subscribers exist.
  - **Process Monitoring:** Automatically removes subscribers when the process is no longer alive.

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

  ## Examples

      iex> {:ok, pid} = PubSubx.start_link(name: :my_pubsub)
      iex> is_pid(pid)
      true
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: get_name(opts))
  end

  @impl true
  @spec init(Keyword.t()) :: {:ok, map()}
  def init(opts) do
    state = %{
      registry: get_registry(get_name(opts))
    }

    {:ok, state}
  end

  @doc """
  Subscribes a given process (`pid`) to a specific `topic`.

  If a `name` is not provided, it defaults to the `PubSubx` module name.

  ## Examples

      iex> PubSubx.subscribe(:my_topic, self(), :my_pubsub)
      :ok
  """
  @spec subscribe(topic, process, process) :: :ok
  def subscribe(topic, pid, name \\ __MODULE__) do
    GenServer.call(name, {:subscribe, {topic, pid}})
  end

  @doc """
  Returns a list of PIDs that are subscribed to the specified `topic`.

  If a `name` is not provided, it defaults to the `PubSubx` module name.

  ## Examples

      iex> PubSubx.subscribers(:my_topic, :my_pubsub)
      [#PID<0.123.0>, #PID<0.456.0>]
  """
  @spec subscribers(topic, process) :: [pid]
  def subscribers(topic, name \\ __MODULE__) do
    GenServer.call(name, {:subscribers, topic})
  end

  @doc """
  Lists all topics that have active subscribers.

  If a `name` is not provided, it defaults to the `PubSubx` module name.

  ## Examples

      iex> PubSubx.topics(:my_pubsub)
      [:my_topic, :another_topic]
  """
  @spec topics(process) :: [topic]
  def topics(name \\ __MODULE__) do
    GenServer.call(name, :topics)
  end

  @doc """
  Publishes a message to the specified `topic`.

  All subscribers to that `topic` will receive the `message`.

  If a `name` is not provided, it defaults to the `PubSubx` module name.

  ## Examples

      iex> PubSubx.publish(:my_topic, "Hello, World!", :my_pubsub)
      :ok
  """
  @spec publish(topic, term(), process) :: :ok
  def publish(topic, message, name \\ __MODULE__) do
    GenServer.cast(name, {:publish, {topic, message}})
  end

  @doc """
  Unsubscribes a given process (`pid`) from the specified `topic`.

  If a `name` is not provided, it defaults to the `PubSubx` module name.

  ## Examples

      iex> PubSubx.unsubscribe(:my_topic, self(), :my_pubsub)
      :ok
  """
  @spec unsubscribe(topic, process, process) :: :ok
  def unsubscribe(topic, pid, name \\ __MODULE__) do
    GenServer.call(name, {:unsubscribe, {topic, pid}})
  end

  @impl true
  @spec handle_cast(term(), map()) :: {:noreply, map()}
  def handle_cast({:publish, {topic, message}}, state) do
    Registry.dispatch(state.registry, topic, fn entries ->
      for {_self, [target: target]} <- entries, do: send(target, message)
    end)

    {:noreply, state}
  end

  @impl true
  @spec handle_call(term(), {pid(), atom}, map()) :: {:reply, term(), map()}
  def handle_call({:subscribe, {topic, pid}}, _from, state) do
    Process.monitor(pid)
    process = get_process(pid)
    {:ok, _} = Registry.register(state.registry, topic, target: process)
    {:reply, :ok, state}
  end

  def handle_call({:unsubscribe, {topic, pid}}, _from, state) do
    process = get_process(pid)
    :ok = unregister(state.registry, topic, process)
    {:reply, :ok, state}
  end

  def handle_call(:topics, _from, state) do
    topics = get_topics(state.registry)
    {:reply, topics, state}
  end

  def handle_call({:subscribers, topic}, _from, state) do
    subscribers =
      state.registry
      |> Registry.values(topic, self())
      |> Enum.map(fn [target: pid] -> pid end)

    {:reply, subscribers, state}
  end

  @impl true
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state.registry
    |> get_topics()
    |> Enum.each(&unregister(state.registry, &1, pid))

    {:noreply, state}
  end

  @doc false
  @spec get_topics(atom) :: [topic]
  defp get_topics(registry), do: Registry.keys(registry, self())

  @doc false
  @spec unregister(atom, topic, pid) :: :ok
  defp unregister(registry, topic, process),
    do: Registry.unregister_match(registry, topic, target: process)

  @doc false
  @spec get_process(process) :: pid
  defp get_process(pid) when is_atom(pid), do: Process.whereis(pid)
  defp get_process(pid), do: pid

  @doc false
  @spec get_registry(atom | binary) :: atom
  defp get_registry(name) do
    registry_name = String.to_atom("PubSubx.Registry.#{name}")

    {:ok, _registry} =
      Registry.start_link(
        keys: :duplicate,
        name: registry_name,
        partitions: System.schedulers_online()
      )

    registry_name
  end

  @doc false
  @spec get_name(Keyword.t()) :: atom
  defp get_name(opts), do: Keyword.get(opts, :name, __MODULE__)
end
