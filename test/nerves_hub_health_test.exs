defmodule NervesHubHealthTest do
  use ExUnit.Case
  alias NervesHubLink.PubSub
  alias NervesHubHealth.DeviceStatus

  defmodule TestReport do
    @behaviour NervesHubHealth.Report
    def timestamp, do: DateTime.utc_now()
    def metrics, do: %{"metric_1" => 1.0, "metric_2" => 2}
    def metadata, do: %{"foo" => "bar"}
    def alarms, do: %{"MyAlarm" => "exciting times"}
    def checks, do: %{"thing_lives" => %{pass: true, note: ""}}
  end

  describe "reporting" do
    test "default health report failing under test" do
      assert %DeviceStatus{
        alarms: %{"Elixir.NervesHubHealth.HealthCheckFailed" => []}
        } = NervesHubHealth.check_health()
    end

    test "custom test report" do
      assert %DeviceStatus{
        timestamp: %DateTime{},
        metrics: %{"metric_1" => 1.0, "metric_2" => 2},
        metadata: %{"foo" => "bar"},
        alarms: %{"MyAlarm" => "exciting times"},
        checks: %{"thing_lives" => %{pass: true, note: ""}}
      } = NervesHubHealth.check_health(TestReport)
    end
  end

  describe "nerves_hub_link pub_sub integration" do
    test "server requests health check" do
      PubSub.subscribe("device")

      # Emulate nerves_hub_link passing us a server event
      PubSub.publish_channel_event("device", "check_health", %{})
      assert_receive %PubSub.Message{type: :msg, topic: "device", event: "check_health", params: %{}}
    end
  end
end
