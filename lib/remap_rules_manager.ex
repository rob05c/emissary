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

  def read_remap_config() do
    case File.read @file_path do
      {:ok, body} ->
        build_remap_config body
      {:error, _} ->
        %{} # \todo warn?
    end
  end

  def comment?(l) do
    String.starts_with? String.trim_leading(l), "#"
  end

  def build_remap_config(file) do
    lines = String.split file, "\n", trim: true
    lines = Enum.reject lines, fn(l) -> comment? l end
    {_, rules} = Enum.map_reduce lines, %{}, fn(line, acc) ->
      ["remap", from, to] = String.split line, " ", trim: true
      acc = Map.put acc, from, to
      {{from, to}, acc}
    end
    rules
  end
end
