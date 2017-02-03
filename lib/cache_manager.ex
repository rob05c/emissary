defmodule Emissary.CacheManager do
  use GenServer

  # \todo change to use Erlang Term Storage
  defmodule CacheData do
    @enforce_keys [:table, :lru_table, :max_bytes]
    defstruct table: "", lru_table: "", bytes: 0, max_bytes: 0
  end

  defmodule Response do
    @enforce_keys [:code, :headers, :body]
    defstruct headers: %{}, body: "", code: 0
  end

  def start_link(name, max_bytes) do
    GenServer.start_link __MODULE__, {name, max_bytes}, name: name
  end

  def get(server, url) do
    GenServer.call server, {:get, url}
  end

  # \todo change val from a string to a struct containing headers etc
  def set(server, url, val) do
    GenServer.cast server, {:set, url, val}
  end

  def init({name, max_bytes}) do
    # \todo determine if read_concurrency should be true. GenServer means only one process ever reads at a time, right?
    :ets.new(name, [:named_table, :public, {:read_concurrency, true}])
    lru_table = :"#{name}_lru"
    :ets.new(lru_table, [:named_table, :ordered_set])

    data = %CacheData{max_bytes: max_bytes, table: name, lru_table: lru_table}
    {:ok, data}
  end

  # freshen bumps url to the top of the LRU. Should be called after someone `get`s the url.
  def freshen(data, url) do
    [{_, lru_index, _}] = :ets.lookup(data.table, url)
    :ets.delete(data.lru_table, lru_index)

      # \todo abstract index-and-insert duplicated in set()
    new_lru_index = :erlang.unique_integer([:monotonic])
    :ets.insert(data.lru_table, {new_lru_index, url})
    :ets.update_element(data.table, url, [{2, new_lru_index}])
    :ok
  end

  # prune deletes entries in the cache, starting with the least-recently-used, until the cache bytes is within max_bytes.
  def prune(data) do
    if data.bytes <= data.max_bytes do
      data
    else
      eldest_lru_index = :ets.first(data.lru_table)
      [{_, url}] = :ets.lookup(data.lru_table, eldest_lru_index)
      [{_, _, val}] = :ets.lookup(data.table, url)
      val_bytes = byte_size val.body
      data = Map.put data, :bytes, data.bytes - val_bytes
      :ets.delete(data.lru_table, eldest_lru_index)
      :ets.delete(data.table, url)
      IO.puts "cache pruned " <> url <> " size " <> Integer.to_string val_bytes
      prune data # recursively prune until the cache is within max_bytes
    end
  end

  def handle_call({:get, url}, _from, data) do
    reply = case :ets.lookup(data.table, url) do
              [{_, _, val}] ->
                freshen(data, url)
                {:ok, val}
              [] ->
                :error
            end
    {:reply, reply, data}
  end

  def handle_cast({:set, url, val}, data) do
    lru_index = :erlang.unique_integer([:monotonic])
    :ets.insert(data.lru_table, {lru_index, url})
    :ets.insert(data.table, {url, lru_index, val})
    val_bytes = byte_size val.body
    new_bytes = data.bytes + val_bytes
    data = Map.put data, :bytes, new_bytes
    IO.puts "cache inserted " <> url <> " size " <> Integer.to_string(val_bytes) <> " (" <> Integer.to_string(new_bytes) <> "/" <> Integer.to_string(data.max_bytes) <> ")"
    data = prune data
    {:noreply, data}
  end

  def headers_to_map(poison_response) do
    {_, headers} = Enum.map_reduce poison_response, %{}, fn(header, acc) ->
      {k, v} = header
      acc = Map.put acc, String.downcase(k), v
      {{k, v}, acc}
    end
    headers
  end

  def to_response(response) do
    body = response.body
    code = response.status_code
    headers = headers_to_map(response.headers)
    %Response{body: body, code: code, headers: headers}
  end

  # fetch gets the given URL from the cache, using all cache control mechanisms.
  # It's assumed the CacheManager is a singleton worker with the package name as the process name
  # If the URL is already in the cache, and hasn't expired, it's returned from cache.
  # If the URL is not in the cache, or has expired, it's requested from its origin, and stored in the cache
  def fetch(request_headers_list, url) do
    case Emissary.CacheManager.get Emissary.CacheManager, url do
      {:ok, val} ->
        IO.puts "found in cache " <> url
        {:ok, val.code, val.headers, val.body} # \todo handle expired entries
      :error ->
        # \todo extract method?
        # \todo request in serial, so we don't flood an origin if a million requests come in at once.
        IO.puts "not found in cache, getting from origin `" <> url <> "`"
        # \todo fix query params
        case Emissary.RequestManager.request(url) do
          {:ok, response} ->
            resp = to_response response

            # \todo add response headers cache-control
            request_headers = headers_to_map(request_headers_list)
            req_cache_control = Emissary.CacheControl.parse(request_headers)
            IO.puts("cache_control:")
            IO.inspect(req_cache_control)
            # \todo check can_cache?
            IO.puts "caching " <> url

            Emissary.CacheManager.set(Emissary.CacheManager, url, resp)
            {:ok, resp.code, resp.headers, resp.body}
          {:error, err} ->
            IO.puts "origin failed with " <> HTTPoison.Error.message(err)
            {:ok, 500, %{}, "origin server error"} # \todo change to generic 500
          _ -> # should never happen
            IO.puts "origin returned unknown value"
            # \todo put in cache, so we don't continuously hit dead origins?
            {:ok, 500, %{}, "internal server error"}
        end
    end
  end
end
