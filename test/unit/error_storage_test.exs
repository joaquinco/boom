defmodule ErrorStorageTest do
  use BoomNotifier.Case

  alias BoomNotifier.ErrorInfo
  alias BoomNotifier.ErrorStorage

  import TestUtils

  @timestamp DateTime.utc_now()

  @error_info ErrorInfo.build(
                %{
                  reason: "Some error information",
                  stack: ["line 1"]
                },
                Plug.Test.conn(:get, "/"),
                :nothing
              )
              |> Map.put(:timestamp, @timestamp)

  @error_hash @error_info.key

  setup do
    clear_error_storage()
  end

  describe "accumulate/1" do
    test "groups errors by type" do
      another_timestamp = DateTime.utc_now()

      another_error_info =
        ErrorInfo.build(
          %{
            reason: "Another error information",
            stack: ["line 2"]
          },
          Plug.Test.conn(:get, "/"),
          :nothing
        )
        |> Map.put(:timestamp, another_timestamp)

      %{key: another_error_hash} = another_error_info

      ErrorStorage.accumulate(@error_info)
      ErrorStorage.accumulate(@error_info)
      ErrorStorage.accumulate(another_error_info)

      %{@error_hash => error_stat_1, ^another_error_hash => error_stat_2} =
        Agent.get(:boom_notifier, & &1)

      assert error_stat_1 == %ErrorStorage{
               __max_storage_capacity__: 1,
               accumulated_occurrences: 2,
               first_occurrence: @timestamp,
               last_occurrence: @timestamp
             }

      assert error_stat_2 == %ErrorStorage{
               __max_storage_capacity__: 1,
               accumulated_occurrences: 1,
               first_occurrence: another_timestamp,
               last_occurrence: another_timestamp
             }
    end
  end

  describe "get_stats/1" do
    test "returns the errors for the proper error kind" do
      ErrorStorage.accumulate(@error_info)
      ErrorStorage.accumulate(@error_info)

      assert ErrorStorage.get_stats(@error_info) ==
               %ErrorStorage{
                 __max_storage_capacity__: 1,
                 accumulated_occurrences: 2,
                 first_occurrence: @timestamp,
                 last_occurrence: @timestamp
               }

      another_timestamp = DateTime.utc_now()

      another_error_info = %ErrorInfo{
        reason: "Another error information",
        stack: ["line 2"],
        timestamp: another_timestamp
      }

      ErrorStorage.accumulate(another_error_info)

      assert ErrorStorage.get_stats(another_error_info) ==
               %ErrorStorage{
                 __max_storage_capacity__: 1,
                 accumulated_occurrences: 1,
                 first_occurrence: another_timestamp,
                 last_occurrence: another_timestamp
               }
    end

    test "returns nil if error info does not exist" do
      assert ErrorStorage.get_stats(@error_info) == nil
    end
  end

  describe "send_notification?/1" do
    test "returns false when count is smaller than the error length" do
      # increase the max capacity to 2
      ErrorStorage.accumulate(@error_info)
      ErrorStorage.increment_max_counter(:exponential, @error_info)
      ErrorStorage.reset(@error_info)
      ErrorStorage.accumulate(@error_info)

      refute ErrorStorage.send_notification?(@error_info)
    end

    test "returns true when error length is greater or equal than count" do
      # creates the error key
      ErrorStorage.accumulate(@error_info)
      # increase the max capacity to 2
      ErrorStorage.increment_max_counter(:exponential, @error_info)
      ErrorStorage.accumulate(@error_info)
      ErrorStorage.accumulate(@error_info)

      another_error_info = %ErrorInfo{
        reason: "Another error information",
        stack: ["line 2"],
        timestamp: @timestamp
      }

      # creates the error key
      ErrorStorage.accumulate(another_error_info)
      # increase the max capacity to 2
      ErrorStorage.increment_max_counter(:exponential, another_error_info)
      ErrorStorage.accumulate(another_error_info)
      ErrorStorage.accumulate(another_error_info)
      ErrorStorage.accumulate(another_error_info)

      assert ErrorStorage.send_notification?(@error_info)
      assert ErrorStorage.send_notification?(another_error_info)
    end

    test "returns false when error key is not stored" do
      refute ErrorStorage.send_notification?(%{key: 123})
    end
  end

  describe "increment_max_counter/2" do
    test "increases the counter when notification trigger is :exponential" do
      ErrorStorage.accumulate(@error_info)

      ErrorStorage.increment_max_counter(:exponential, @error_info)
      [error_stat] = Agent.get(:boom_notifier, fn state -> state end) |> Map.values()

      assert %{__max_storage_capacity__: 2} = error_stat

      ErrorStorage.increment_max_counter(:exponential, @error_info)
      [error_stat] = Agent.get(:boom_notifier, fn state -> state end) |> Map.values()

      assert %{__max_storage_capacity__: 4} = error_stat

      ErrorStorage.increment_max_counter(:exponential, @error_info)
      [error_stat] = Agent.get(:boom_notifier, fn state -> state end) |> Map.values()

      assert %{__max_storage_capacity__: 8} = error_stat
    end

    test "increases the counter when notification trigger is :exponential and :limit is set" do
      ErrorStorage.accumulate(@error_info)

      ErrorStorage.increment_max_counter([exponential: [limit: 5]], @error_info)
      [error_stat] = Agent.get(:boom_notifier, fn state -> state end) |> Map.values()

      assert %{__max_storage_capacity__: 2} = error_stat

      ErrorStorage.increment_max_counter([exponential: [limit: 5]], @error_info)
      [error_stat] = Agent.get(:boom_notifier, fn state -> state end) |> Map.values()

      assert %{__max_storage_capacity__: 4} = error_stat

      ErrorStorage.increment_max_counter([exponential: [limit: 5]], @error_info)
      [error_stat] = Agent.get(:boom_notifier, fn state -> state end) |> Map.values()

      assert %{__max_storage_capacity__: 5} = error_stat
    end

    test "does not increase the counter when notification_trigger is :always" do
      ErrorStorage.accumulate(@error_info)

      ErrorStorage.increment_max_counter(:always, @error_info)
      [error_stat] = Agent.get(:boom_notifier, fn state -> state end) |> Map.values()

      assert %{__max_storage_capacity__: 1} = error_stat

      ErrorStorage.increment_max_counter(:always, @error_info)
      [error_stat] = Agent.get(:boom_notifier, fn state -> state end) |> Map.values()

      assert %{__max_storage_capacity__: 1} = error_stat

      ErrorStorage.increment_max_counter(:always, @error_info)
    end

    test "updates the proper error max capacity" do
      another_error_info =
        ErrorInfo.build(
          %{
            reason: "Another error information",
            stack: ["line 2"]
          },
          Plug.Test.conn(:get, "/"),
          :nothing
        )
        |> Map.put(:timestamp, @timestamp)

      %{key: another_error_hash} = another_error_info

      ErrorStorage.accumulate(@error_info)
      ErrorStorage.accumulate(another_error_info)

      ErrorStorage.increment_max_counter(:exponential, @error_info)

      %{@error_hash => error_stat_1, ^another_error_hash => error_stat_2} =
        Agent.get(:boom_notifier, & &1)

      assert %{__max_storage_capacity__: 2} = error_stat_1

      assert %{__max_storage_capacity__: 1} = error_stat_2
    end
  end

  describe "reset/1" do
    test "can handle unsaved errors" do
      stats_before = ErrorStorage.get_stats(@error_info)
      ErrorStorage.reset(@error_info)
      stats_after = ErrorStorage.get_stats(@error_info)

      assert is_nil(stats_before)

      assert %{accumulated_occurrences: 0, first_occurrence: nil, last_occurrence: nil} =
               stats_after
    end

    test "resets accumulated and timestamps but not __max_storage_capacity__" do
      Agent.update(:boom_notifier, fn state ->
        state
        |> Map.put(
          @error_hash,
          %ErrorStorage{
            accumulated_occurrences: 10,
            first_occurrence: DateTime.utc_now(),
            last_occurrence: DateTime.utc_now(),
            __max_storage_capacity__: 20
          }
        )
      end)

      ErrorStorage.reset(@error_info)
      stats = ErrorStorage.get_stats(@error_info)

      assert %{accumulated_occurrences: 0, first_occurrence: nil, last_occurrence: nil} = stats
      assert %{__max_storage_capacity__: 20} = stats
    end
  end
end
