defmodule NervesHubHealth do
  use GenServer

  alias NervesHubHealth.DeviceStatus
  alias NervesHubLink.PubSub

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    state = %{}
    PubSub.subscribe("device")
    {:ok, state}
  end

  def check_health(default_report \\ NervesHubHealth.DefaultReport) do
    report = Application.get_env(:nerves_hub_health, :report, default_report)

    if report do
      DeviceStatus.new(
        timestamp: report.timestamp(),
        metadata: report.metadata(),
        alarms: report.alarms(),
        metrics: report.metrics(),
        checks: report.checks()
      )
    end
  rescue
    _ ->
      :alarm_handler.set_alarm({NervesHubHealth.HealthCheckFailed, []})

      DeviceStatus.new(
        timestamp: DateTime.utc_now(),
        metadata: %{},
        alarms: %{to_string(NervesHubHealth.HealthCheckFailed) => []},
        metrics: %{},
        checks: %{}
      )
  end

  @impl GenServer
  def handle_info({:broadcast, :msg, "device", "check_health", _params}, state) do
    case check_health() do
      %DeviceStatus{} = ds ->
        PubSub.publish_to_hub("device", "health_check_report", %{value: ds})

      {:error, reason} ->
        Logger.error("Failed to call health check: #{inspect(reason)}")

      nil ->
        Logger.error("Health check returned a nil value.")
    end


    {:noreply, state}
  end

  def handle_info({:broadcast, _, _, _}, state) do
    {:noreply, state}
  end
end
