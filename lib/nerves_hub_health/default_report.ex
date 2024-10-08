defmodule NervesHubHealth.DefaultReport do
  @moduledoc """
  A default health report implementation with support for easily adding
  new metadata, metrics and such via config.
  """
  @behaviour NervesHubHealth.Report
  alias NervesHubHealth.Report
  require Logger

  @impl Report
  def timestamp do
    DateTime.utc_now()
  end

  @impl Report
  def metadata do
    # A lot of typical metadata is included in the join
    # we can skip that here
    # NervesHub is responsible for joining that into the stored data
    metadata_from_config()
  end

  @impl Report
  def alarms do
    for {id, description} <- :alarm_handler.get_alarms(), into: %{} do
      try do
        {inspect(id), inspect(description)}
      catch
        _, _ ->
          {"bad alarm term", ""}
      end
    end
  end

  @impl Report
  def metrics do
    [
      metrics_from_config(),
      cpu_temperature(),
      load_averages(),
      memory()
    ]
    |> Enum.reduce(%{}, &Map.merge/2)
  end

  @impl Report
  def checks do
    checks_from_config()
  end

  @impl Report
  def connectivity do
    [
      connectivity_from_config(),
      vintage_net()
    ]
    |> Enum.reduce(%{}, &Map.merge/2)
  end

  defp vof({mod, fun, args}), do: apply(mod, fun, args)
  defp vof(val), do: val

  defp metadata_from_config do
    metadata = Application.get_env(:nerves_hub_health, :metadata, %{})

    for {key, val_or_fun} <- metadata, into: %{} do
      {inspect(key), vof(val_or_fun)}
    end
  end

  defp metrics_from_config do
    metrics = Application.get_env(:nerves_hub_health, :metrics, %{})

    for {key, val_or_fun} <- metrics, into: %{} do
      {inspect(key), vof(val_or_fun)}
    end
  end

  defp checks_from_config do
    checks = Application.get_env(:nerves_hub_health, :checks, %{})

    for {key, val_or_fun} <- checks, into: %{} do
      {inspect(key), vof(val_or_fun)}
    end
  end

  defp connectivity_from_config do
    connectivity = Application.get_env(:nerves_hub_health, :connectivity, %{})

    for {key, val_or_fun} <- connectivity, into: %{} do
      {inspect(key), vof(val_or_fun)}
    end
  end

  defp cpu_temperature do
    with {:ok, content} <- File.read("/sys/class/thermal/thermal_zone0/temp"),
         {millidegree_c, _} <- Integer.parse(content) do
      %{cpu_temp: millidegree_c / 1000}
    else
      _ -> cpu_temperature_rpi()
    end
  end

  defp cpu_temperature_rpi do
    with {result, 0} <- System.cmd("/usr/bin/vcgencmd", ["measure_temp"]) do
      %{"temp" => temp} = Regex.named_captures(~r/temp=(?<temp>[\d.]+)/, result)
      {temp, _} = Integer.parse(temp)
      %{cpu_temp: temp}
    else
      _ -> %{}
    end
  end

  defp load_averages do
    with {:ok, data_str} <- File.read("/proc/loadavg"),
         [min1, min5, min15, _, _] <- String.split(data_str, " "),
         {min1, _} <- Float.parse(min1),
         {min5, _} <- Float.parse(min5),
         {min15, _} <- Float.parse(min15) do
      %{load_1min: min1, load_5min: min5, load_15min: min15}
    else
      _ -> %{}
    end
  end

  defp memory do
    {free_output, 0} = System.cmd("free", [])
    [_title_row, memory_row | _] = String.split(free_output, "\n")
    [_title_column | memory_columns] = String.split(memory_row)
    [size_kb, used_kb, _, _, _, _] = Enum.map(memory_columns, &String.to_integer/1)
    size_mb = round(size_kb / 1000)
    used_mb = round(used_kb / 1000)
    used_percent = round(used_mb / size_mb * 100)

    %{size_mb: size_mb, used_mb: used_mb, used_percent: used_percent}
  end

  def vintage_net() do
    case Application.ensure_loaded(:vintage_net) do
      :ok ->
        ifs = VintageNet.all_interfaces() |> Enum.reject(&(&1 == "lo"))

        PropertyTable.get_all(VintageNet)
        |> Enum.reduce(%{}, fn {key, value}, acc ->
          # Get all data from nuisance PropertyTable structure
          case key do
            ["interface", interface, subkey] ->
              if interface in ifs do
                kv =
                  acc
                  |> Map.get(interface, %{})
                  |> Map.put(subkey, value)

                Map.put(acc, interface, kv)
              else
                acc
              end

            _ ->
              acc
          end
        end)
        |> Enum.reduce(%{}, fn {interface, kv}, acc ->
          case kv do
            %{
              "type" => type,
              "present" => present,
              "state" => state,
              "connection" => connection_status
            } ->
              Map.put(acc, interface, %{
                type: vintage_net_type(type),
                present: present,
                state: state,
                connection_status: connection_status,
                metrics: %{},
                metadata: %{}
              })

            _ ->
              acc
          end
        end)

      {:error, _} ->
        # Probably VintageNet doesn't exist
        %{}
    end
  end

  defp vintage_net_type(VintageNetWiFi), do: :wifi
  defp vintage_net_type(VintageNetEthernet), do: :ethernet
  defp vintage_net_type(VintageNetQMI), do: :mobile
  defp vintage_net_type(VintageNetMobile), do: :mobile
  defp vintage_net_type(_), do: :unknown
end
