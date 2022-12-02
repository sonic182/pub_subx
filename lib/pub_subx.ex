defmodule PubSubx do
  @moduledoc """
  Documentation for `PubSubx`.
  """

  use GenServer

  @type topic :: atom | binary
  @type process :: atom | pid

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

  @spec subscribe(topic, process, process) :: :ok
  def subscribe(topic, pid, name \\ __MODULE__) do
    GenServer.call(name, {:subscribe, {topic, pid}})
  end

  @spec subscribers(topic, process) :: [pid]
  def subscribers(topic, name \\ __MODULE__) do
    GenServer.call(name, {:subscribers, topic})
  end

  @spec topics(process) :: [topic]
  def topics(name \\ __MODULE__) do
    GenServer.call(name, :topics)
  end

  @spec publish(topic, term(), process) :: :ok
  def publish(topic, message, name \\ __MODULE__) do
    GenServer.cast(name, {:publish, {topic, message}})
  end

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

  defp get_topics(registry), do: Registry.keys(registry, self())

  defp unregister(registry, topic, process),
    do: Registry.unregister_match(registry, topic, target: process)

  @spec get_process(process) :: pid
  defp get_process(pid) when is_atom(pid), do: Process.whereis(pid)
  defp get_process(pid), do: pid

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

  @spec get_name(Keyword.t()) :: atom
  defp get_name(opts), do: Keyword.get(opts, :name, __MODULE__)
end
