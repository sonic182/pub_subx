defmodule PubSubx.Auto do
  @moduledoc """
  Provides a macro to automatically generate common `PubSubx` functionality
  for a module, including function specifications.

  ## Usage

  To use this module, include `PubSubx.Auto` in your module and provide the `:name` option:

      defmodule MyPubSub do
        use PubSubx.Auto, name: MyPubSub
      end

  This will create functions such as `start_link/0`, `subscribe/2`, `publish/2`, etc., with specifications that use the provided `name` for `PubSubx` operations.

  ## Functions

  The following functions are automatically defined in the module:

    - `start_link/0`: Starts the `PubSubx` server with the specified name.
    - `subscribe/2`: Subscribes a given process to a topic.
    - `subscribers/1`: Retrieves a list of subscribers for a given topic.
    - `topics/0`: Lists all topics with at least one subscriber.
    - `publish/2`: Publishes a message to a given topic.
    - `unsubscribe/2`: Unsubscribes a given process from a topic.
  """

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)

    quote do
      @spec pname() :: module()
      defp pname, do: unquote(name)

      @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, opts}
        }
      end

      @doc """
      Starts the `PubSubx` server with the specified name.
      """
      @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
      def start_link(opts \\ []) do
        opts = Keyword.merge([name: pname()], opts)
        PubSubx.start_link(opts)
      end

      @doc """
      Subscribes a given process to a topic.
      """
      @spec subscribe(topic :: atom | binary, pid()) :: :ok
      def subscribe(topic, pid) do
        PubSubx.subscribe(pname(), topic, pid)
      end

      @doc """
      Retrieves a list of subscribers for a given topic.
      """
      @spec subscribers(topic :: atom | binary) :: [pid()]
      def subscribers(topic) do
        PubSubx.subscribers(pname(), topic)
      end

      @doc """
      Lists all topics with at least one subscriber.
      """
      @spec topics() :: [atom | binary]
      def topics do
        PubSubx.topics(pname())
      end

      @doc """
      Publishes a message to a given topic.
      """
      @spec publish(topic :: atom | binary, message :: term()) :: :ok
      def publish(topic, message) do
        PubSubx.publish(pname(), topic, message)
      end

      @doc """
      Unsubscribes a given process from a topic.
      """
      @spec unsubscribe(topic :: atom | binary, pid()) :: :ok
      def unsubscribe(topic, pid) do
        PubSubx.unsubscribe(pname(), topic, pid)
      end
    end
  end
end
