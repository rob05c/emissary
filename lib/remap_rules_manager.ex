defmodule Emissary.RemapManager do
  use GenServer

  @file_path "remap.config"

  def start_link(name) do
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  def get(server, rule) do
    GenServer.call(server, {:lookup, rule})
  end

  def init(:ok) do
    rules = read_remap_config()
    {:ok, rules}
  end

  def handle_call({:lookup, rule}, _from, rules) do
    {:reply, Map.fetch(rules, rule), rules}
  end

  defp read_remap_config() do
    case File.read @file_path do
      {:ok, body} ->
        build_remap_config body
      {:error, _} ->
        %{} # \todo warn?
    end
  end

  defp comment?(l) do
    String.starts_with? String.trim_leading(l), "#"
  end

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
