defmodule NervesHubHealth.Report do
    @callback timestamp() :: DateTime.t()
    @callback metadata() :: %{String.t() => String.t()}
    @callback alarms() :: %{String.t() => String.t()}
    @callback metrics() :: %{String.t() => number()}
    @callback checks() :: %{String.t() => %{pass: boolean(), note: String.t()}}
end
  