defmodule PubSubx.Event do
  @moduledoc """
  Event envelope delivered to `PubSubx` subscribers.
  """

  @enforce_keys [:topic, :payload, :timestamp]
  defstruct [:topic, :payload, :timestamp, metadata: %{}, correlation_id: nil, trace_id: nil]

  @type t :: %__MODULE__{
          topic: PubSubx.topic(),
          payload: term(),
          timestamp: DateTime.t(),
          metadata: map(),
          correlation_id: term() | nil,
          trace_id: term() | nil
        }
end
