defmodule Emissary.RequestManager do
  use GenServer

  defmodule Response do
    @enforce_keys [:code, :headers, :body, :request_time, :response_time]
    defstruct headers: %{}, body: "", code: 0, request_headers: %{}, request_time: nil, response_time: nil
  end

  defmodule Data do
    @enforce_keys [:request_pids, :revalidate_pids]
    defstruct request_pids: %{}, revalidate_pids: %{}
  end

  def headers_to_map(poison_response) do
    Enum.reduce poison_response, %{}, fn(header, acc) ->
      {k, v} = header
      Map.put(acc, String.downcase(k), v)
    end
  end

  defp to_response(response, request_headers, request_time, response_time) do
    body = response.body
    code = response.status_code
    headers = headers_to_map(response.headers)
    %Response{body: body, code: code, headers: headers, request_headers: request_headers, request_time: request_time, response_time: response_time}
  end

  defp to_response(response_code, response_body, request_headers, request_time, response_time) do
    body = response_body
    code = response_code
    headers = %{}
    %Response{body: body, code: code, headers: headers, request_headers: request_headers, request_time: request_time, response_time: response_time}
  end

  def start_link(name) do
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  def init(:ok) do
    data = %Data{request_pids: %{}, revalidate_pids: %{}}
    {:ok, data}
  end

  defp do_request(url) do
    request_time = DateTime.utc_now()
    # TODO: add request headers
    response = HTTPoison.get(url, [], [])
    response_time = DateTime.utc_now()
    GenServer.cast Emissary.RequestManager, {:response, {url, response, request_time, response_time}}
  end

  # TODO: add other revalidate mechanisms, like ETAG
  defp do_revalidate(url, old_response) do
    request_time = DateTime.utc_now()

    headers = [] # TODO: add old_response.request_headers?
    headers = case Map.fetch(old_response.headers, "date") do
                {:ok, http_date} ->
                  [{"if-modified-since", http_date}|headers]
                :error ->
                  headers
              end

    IO.puts "revalidating with headers "
    IO.inspect headers
    IO.puts " for " <> url
    response = HTTPoison.get(url, headers, [])

    response_time = DateTime.utc_now()
    GenServer.cast Emissary.RequestManager, {:revalidate_response, {url, response, request_time, response_time}}
  end

  def handle_cast({:response, {url, response, request_time, response_time}}, data) do
    url_pids = data.request_pids
    pids = Map.fetch! url_pids, url
    Enum.each pids, fn(pid) ->
      send pid, {:okay, response, request_time, response_time}
    end
    url_pids = Map.delete url_pids, url
    data = %{data | request_pids: url_pids}
    {:noreply, data}
  end

  def handle_cast({:revalidate_response, {url, response, request_time, response_time}}, data) do
    url_pids = data.revalidate_pids
    pids = Map.fetch! url_pids, url
    Enum.each pids, fn(pid) ->
      send pid, {:ok, response, request_time, response_time}
    end
    url_pids = Map.delete url_pids, url
    data = %{data | revalidate_pids: url_pids}
    {:noreply, data}
  end

  # TODO: add request headers
  def handle_cast({:request, {url, pid}}, data) do
    url_pids = data.request_pids
    pids = Map.get url_pids, url, []
    if length(pids) == 0 do
      Task.start fn() -> do_request(url) end
    else
      nil
    end
    pids = [pid | pids]
    url_pids = Map.put url_pids, url, pids
    data = %{data | request_pids: url_pids}
    {:noreply, data}
  end

  # TODO: abstract duplicate pid-reply code?
  def handle_cast({:revalidate, {url, response, pid}}, data) do
    url_pids = data.revalidate_pids
    pids = Map.get url_pids, url, []
    if length(pids) == 0 do
      Task.start fn() -> do_revalidate(url, response) end
    else
      nil
    end
    pids = [pid | pids]
    url_pids = Map.put url_pids, url, pids
    data = %{data | revalidate_pids: url_pids}
    {:noreply, data}
  end

  def request(url, request_headers_list) do
    GenServer.cast Emissary.RequestManager, {:request, {url, self()}}
    request_headers = headers_to_map(request_headers_list)
    receive do
      {:okay, poison_response, request_time, response_time} ->
        case poison_response do
          {:ok, response} ->
            to_response response, request_headers, request_time, response_time
          {:error, err} ->
            # TODO: 504?
            to_response 500, "origin server error", request_headers, request_time, response_time
          unknown ->
            IO.puts "origin returned unknown value"
            IO.inspect unknown
            to_response 500, "internal server error", request_headers, request_time, response_time
        end
    end
  end

  def revalidate(url, old_resp) do
    GenServer.cast Emissary.RequestManager, {:revalidate, {url, old_resp, self()}}
    receive do
      {:ok, poison_response, request_time, response_time} ->
        case poison_response do
          {:ok, response} ->
            case response.status_code do
              304 ->
                IO.puts "revalidate got 304 for " <> url
                # defstruct headers: %{}, body: "", code: 0, request_headers: %{}, request_time: nil, response_time: nil
                %Response{
                  body:            old_resp.body,
                  code:            old_resp.code,
                  request_headers: old_resp.request_headers,
                  request_time:    request_time,
                  response_time:   response_time,
                  headers:         Enum.reduce(response.headers, old_resp.headers, fn({k, v}, headers) ->
                    Map.put(headers, k, v)
                  end)}
              _ ->
                IO.puts "revalidate got " <> Integer.to_string(response.status_code) <> " from " <> url
                to_response response, old_resp.request_headers, request_time, response_time
            end

          {:error, err} ->
            # TODO: 504?
            to_response 500, "origin server error", old_resp.request_headers, request_time, response_time
          unknown ->
            IO.puts "revalidate origin returned unknown value"
            IO.inspect unknown
            to_response 500, "revalidate internal server error", old_resp.request_headers, request_time, response_time
        end
    end

# response.status_code
  end
end
