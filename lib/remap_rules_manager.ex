defmodule Emissary.RemapManager do
  use GenServer

  @file_path "remap.config"

  @spec start_link(module) :: GenServer.on_start
  def start_link(name) do
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @spec get(GenServer.server, String.t) :: String.t
  def get(server, rule) do
    GenServer.call(server, {:lookup, rule})
  end

  @spec init(:ok) :: {:ok, %{String.t => String.t}}
  def init(:ok) do
    rules = read_remap_config()
    {:ok, rules}
  end

  @spec handle_call({:lookup, String.t}, any, %{String.t => String.t}) :: {:reply, String.t}
  def handle_call({:lookup, rule}, _from, rules) do
    {:reply, Map.fetch(rules, rule), rules}
  end

  @spec read_remap_config() :: map
  defp read_remap_config do
    case File.read @file_path do
      {:ok, body} ->
        build_remap_config body
      {:error, _} ->
        %{} # TODO warn?
    end
  end

  @spec comment?(String.t) :: boolean
  defp comment?(l) do
    String.starts_with? String.trim_leading(l), "#"
  end

  @spec build_remap_config(String.t) :: %{String.t => String.t}
  defp build_remap_config(file) do
    file
    |> String.split("\n", trim: true)
    |> Enum.reject(fn(l) -> comment?(l) end)
    |> Enum.reduce(%{}, fn(line, acc) ->
      ["remap", from, to] = String.split(line, " ", trim: true)
      Map.put(acc, from, to)
    end)
  end
end
