defmodule ApothecaryWeb.ChatLive.ChatMessage do
  @moduledoc "Chat message struct and constructors."

  @type msg_type :: :system | :user | :brewer_event | :oracle_response | :status | :error | :live_status | :live_info

  @type t :: %__MODULE__{
          id: integer(),
          type: msg_type(),
          source: String.t(),
          context_label: String.t(),
          body: String.t() | {:tree, list()},
          timestamp: DateTime.t(),
          metadata: map()
        }

  defstruct [:id, :type, :source, :context_label, :body, :timestamp, metadata: %{}]

  def system(counter, body, metadata \\ %{}) do
    %__MODULE__{
      id: counter,
      type: :system,
      source: "apothecary",
      context_label: "",
      body: body,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
  end

  def user(counter, body, context_label) do
    %__MODULE__{
      id: counter,
      type: :user,
      source: "you",
      context_label: context_label,
      body: body,
      timestamp: DateTime.utc_now()
    }
  end

  def brewer_event(counter, body, source, metadata \\ %{}) do
    %__MODULE__{
      id: counter,
      type: :brewer_event,
      source: source,
      context_label: "",
      body: body,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
  end

  def oracle(counter, body) do
    %__MODULE__{
      id: counter,
      type: :oracle_response,
      source: "oracle",
      context_label: "oracle",
      body: body,
      timestamp: DateTime.utc_now()
    }
  end

  def status(counter, body) do
    %__MODULE__{
      id: counter,
      type: :status,
      source: "apothecary",
      context_label: "",
      body: body,
      timestamp: DateTime.utc_now()
    }
  end

  def error(counter, body) do
    %__MODULE__{
      id: counter,
      type: :error,
      source: "apothecary",
      context_label: "",
      body: body,
      timestamp: DateTime.utc_now()
    }
  end

  def live_status(counter) do
    %__MODULE__{
      id: counter,
      type: :live_status,
      source: "apothecary",
      context_label: "",
      body: "",
      timestamp: DateTime.utc_now()
    }
  end

  def live_info(counter, wt_id) do
    %__MODULE__{
      id: counter,
      type: :live_info,
      source: "apothecary",
      context_label: "",
      body: "",
      timestamp: DateTime.utc_now(),
      metadata: %{wt_id: wt_id}
    }
  end
end
