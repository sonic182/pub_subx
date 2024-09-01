defmodule PubSubx.Auto do
  @moduledoc """
  Provides a macro to automatically generate common `PubSubx` functionality
  for a module, including function specifications.
  """

  defmacro __using__(opts) do
    name = Keyword.get(opts, :name)

    quote do
      defp pname, do: unquote(name) || __MODULE__

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {PubSubx, :start_link, opts}
        }
      end

      @doc """
      Starts the `PubSubx` server with the specified name.
      """
      def start_link() do
        PubSubx.start_link(name: pname())
      end

      @doc """
      Subscribes a given process to a topic.
      """
      def subscribe(topic, pid) do
        PubSubx.subscribe(pname(), topic, pid)
      end

      @doc """
      Retrieves a list of subscribers for a given topic.
      """
      def subscribers(topic) do
        PubSubx.subscribers(pname(), topic)
      end

      @doc """
      Lists all topics with at least one subscriber.
      """
      def topics() do
        PubSubx.topics(pname())
      end

      @doc """
      Publishes a message to a given topic.
      """
      def publish(topic, message) do
        PubSubx.publish(pname(), topic, message)
      end

      @doc """
      Unsubscribes a given process from a topic.
      """
      def unsubscribe(topic, pid) do
        PubSubx.unsubscribe(pname(), topic, pid)
      end
    end
  end
end
