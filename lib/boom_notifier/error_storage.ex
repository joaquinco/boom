defmodule BoomNotifier.ErrorStorage do
  @moduledoc false

  # Keeps track of the errors grouped by type and a counter so the notifier
  # knows the next time it should be executed

  alias BoomNotifier.ErrorInfo

  @enforce_keys [:accumulated_occurrences, :first_occurrence, :last_occurrence]
  defstruct [
    :accumulated_occurrences,
    :first_occurrence,
    :last_occurrence,
    :__max_storage_capacity__
  ]

  @type t :: %__MODULE__{}
  @type error_strategy :: :always | :exponential | [exponential: [limit: non_neg_integer()]]

  use Agent, start: {__MODULE__, :start_link, []}

  @spec start_link() :: Agent.on_start()
  def start_link do
    Agent.start_link(fn -> %{} end, name: :boom_notifier)
  end

  @doc """
  Stores information about how many times an error occurred.

  This information is stored in a map where the key is the error info hash.
  Every time this function is called with an error info, the accumulated
  occurrences is increased and it also updates the first and last time it
  happened.
  """
  @spec accumulate(ErrorInfo.t()) :: :ok
  def accumulate(error_info) do
    %{key: error_hash_key} = error_info
    timestamp = error_info.timestamp || DateTime.utc_now()

    Agent.update(
      :boom_notifier,
      &Map.update(
        &1,
        error_hash_key,
        default_error_storage_info()
        |> Map.merge(%{
          accumulated_occurrences: 1,
          first_occurrence: timestamp,
          last_occurrence: timestamp
        }),
        fn error_storage_item ->
          error_storage_item
          |> Map.update!(:accumulated_occurrences, fn current -> current + 1 end)
          |> Map.update!(:first_occurrence, fn first_occurrence ->
            first_occurrence || timestamp
          end)
          |> Map.update!(:last_occurrence, fn _ -> timestamp end)
        end
      )
    )
  end

  @doc """
  Given an error info, it returns the aggregated info stored in the agent.
  """
  @spec get_stats(ErrorInfo.t()) :: %__MODULE__{}
  def get_stats(error_info) do
    %{key: error_hash_key} = error_info

    Agent.get(:boom_notifier, fn state -> state end)
    |> Map.get(error_hash_key)
  end

  @doc """
  Tells whether a notification for an error info is ready to be sent.

  Returns true if the accumulated_occurrences is above or equal to the max
  storage capacity.
  """
  @spec send_notification?(ErrorInfo.t()) :: boolean()
  def send_notification?(error_info) do
    %{key: error_hash_key} = error_info

    error_storage_item =
      Agent.get(:boom_notifier, fn state -> state end)
      |> Map.get(error_hash_key)

    do_send_notification?(error_storage_item)
  end

  @doc """
  Increment the max counter used for counting error throttling
  """
  @spec increment_max_counter(error_strategy, ErrorInfo.t()) :: :ok
  def increment_max_counter(:exponential, error_info) do
    do_increment_max_counter(error_info, &(&1 * 2))
  end

  def increment_max_counter([exponential: [limit: limit]], error_info) do
    do_increment_max_counter(error_info, &min(&1 * 2, limit))
  end

  def increment_max_counter(:always, error_info) do
    do_increment_max_counter(error_info, fn _ -> 1 end)
  end

  defp do_increment_max_counter(error_info, update_callback) do
    %{key: error_hash_key} = error_info

    Agent.update(
      :boom_notifier,
      &Map.update(
        &1,
        error_hash_key,
        default_error_storage_info(),
        fn data -> Map.update!(data, :__max_storage_capacity__, update_callback) end
      )
    )
  end

  @spec reset(ErrorInfo.t()) :: ErrorStorage.t()
  def reset(error_info) do
    %{key: error_hash_key} = error_info

    Agent.update(
      :boom_notifier,
      &Map.update(
        &1,
        error_hash_key,
        default_error_storage_info(),
        fn error_storage_item ->
          error_storage_item
          |> Map.merge(%{
            accumulated_occurrences: 0,
            first_occurrence: nil,
            last_occurrence: nil
          })
        end
      )
    )
  end

  @spec do_send_notification?(ErrorInfo.t() | nil) :: boolean()
  defp do_send_notification?(nil), do: false

  defp do_send_notification?(error_storage_item) do
    accumulated_occurrences = Map.get(error_storage_item, :accumulated_occurrences)
    max_storage_capacity = Map.get(error_storage_item, :__max_storage_capacity__)

    accumulated_occurrences >= max_storage_capacity
  end

  defp default_error_storage_info do
    %__MODULE__{
      accumulated_occurrences: 0,
      first_occurrence: nil,
      last_occurrence: nil,
      __max_storage_capacity__: 1
    }
  end
end
