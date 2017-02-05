defmodule Emissary.RequestManager do
  use GenServer

  def start_link(name) do
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  def get(server, rule) do
    GenServer.call(server, {:get, rule})
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def do_request(url) do
    request_time = DateTime.utc_now()
    response = HTTPoison.get(url, [], [])
    response_time = DateTime.utc_now()
    GenServer.cast Emissary.RequestManager, {:response, {url, response, request_time, response_time}}
  end

  def handle_cast({:response, {url, response, request_time, response_time}}, url_pids) do
    pids = Map.fetch! url_pids, url
    Enum.each pids, fn(pid) ->
      send pid, {:ok, response, request_time, response_time}
    end
    url_pids = Map.delete url_pids, url
    {:noreply, url_pids}
  end

  def handle_cast({:request, {url, pid}}, url_pids) do
    pids = Map.get url_pids, url, []
    if length(pids) == 0 do
      Task.start fn() -> do_request(url) end
    else
      nil
    end
    pids = [pid | pids]
    url_pids = Map.put url_pids, url, pids
    {:noreply, url_pids}
  end

  def request(url) do
    GenServer.cast Emissary.RequestManager, {:request, {url, self()}}
    receive do
      {:ok, response, request_time, response_time} ->
        {response, request_time, response_time}
    end
  end
end
