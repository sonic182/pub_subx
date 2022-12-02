defmodule PubSubx do
  @moduledoc """
  Documentation for `PubSubx`.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: get_name(opts))
  end

  def init(opts) do
    state = %{
      registry: get_registry(get_name(opts))
    }

    {:ok, state}
  end

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

  defp get_name(opts), do: Keyword.get(opts, :name, __MODULE__)

  def subscribe(topic, pid, name \\ __MODULE__) do
    GenServer.call(name, {:subscribe, {topic, pid}})
  end

  def subscribers(topic, name \\ __MODULE__) do
    GenServer.call(name, {:subscribers, topic})
  end

  def topics(name \\ __MODULE__) do
    GenServer.call(name, :topics)
  end

  def publish(topic, message, name \\ __MODULE__) do
    GenServer.cast(name, {:publish, {topic, message}})
  end

  def unsubscribe(topic, pid, name \\ __MODULE__) do
    GenServer.call(name, {:unsubscribe, {topic, pid}})
  end

  def handle_cast({:publish, {topic, message}}, state) do
    Registry.dispatch(state.registry, topic, fn entries ->
      for {_self, [target: target]} <- entries, do: send(target, message)
    end)

    {:noreply, state}
  end

  def handle_call({:subscribe, {topic, pid}}, _from, state) do
    process = get_process(pid)
    {:ok, _} = Registry.register(state.registry, topic, target: process)
    {:reply, :ok, state}
  end

  def handle_call({:unsubscribe, {topic, pid}}, _from, state) do
    process = get_process(pid)
    :ok = Registry.unregister_match(state.registry, topic, target: process)
    {:reply, :ok, state}
  end

  def handle_call(:topics, _from, state) do
    keys = Registry.keys(state.registry, self())
    {:reply, keys, state}
  end

  def handle_call({:subscribers, topic}, _from, state) do
    subscribers =
      state.registry
      |> Registry.values(topic, self())
      |> Enum.map(fn [target: pid] -> pid end)

    {:reply, subscribers, state}
  end

  defp get_process(pid) when is_atom(pid), do: Process.whereis(pid)
  defp get_process(pid), do: pid
end
