defmodule Emissary.CacheManager do
  use GenServer
  alias Emissary.RequestManager.Response, as: Response
  alias Emissary.CacheControl, as: CacheControl
  alias Emissary.CacheManager, as: CacheManager
  alias Emissary.RequestManager, as: RequestManager
  alias Emissary.Rules, as: Rules

  # TODO: change to use Erlang Term Storage
  defmodule CacheData do
    @enforce_keys [:table, :lru_table, :max_bytes]
    defstruct table: "", lru_table: "", bytes: 0, max_bytes: 0
  end

  @spec start_link(String.t, binary) :: GenServer.on_start
  def start_link(name, max_bytes) do
    GenServer.start_link __MODULE__, {name, max_bytes}, name: name
  end

  @spec get(GenServer.server, String.t) :: {:reply, {:ok, Response} | :error, %CacheData{}}
  defp get(server, url) do
    GenServer.call server, {:get, url}
  end

  @spec set(GenServer.server, String.t, Response) :: :ok
  defp set(server, url, val) do
    GenServer.cast server, {:set, url, val}
  end

  @spec delete(GenServer.server, String.t) :: :ok
  defp delete(server, url) do
    GenServer.cast server, {:delete, url}
  end

  @spec init({String.t, integer}) :: {:ok, %CacheData{}}
  def init({name, max_bytes}) do
    # TODO: determine if read_concurrency should be true. GenServer means only one process ever reads at a time, right?
    :ets.new(name, [:named_table, :public, {:read_concurrency, true}])
    lru_table = :"#{name}_lru"
    :ets.new(lru_table, [:named_table, :ordered_set])

    data = %CacheData{max_bytes: max_bytes, table: name, lru_table: lru_table}
    {:ok, data}
  end

  # freshen bumps url to the top of the LRU. Should be called after someone `get`s the url.
  @spec freshen(%CacheData{}, String.t) :: :ok
  defp freshen(data, url) do
    [{_, lru_index, _}] = :ets.lookup(data.table, url)
    :ets.delete(data.lru_table, lru_index)

      # TODO: abstract index-and-insert duplicated in set()
    new_lru_index = :erlang.unique_integer([:monotonic])
    :ets.insert(data.lru_table, {new_lru_index, url})
    :ets.update_element(data.table, url, [{2, new_lru_index}])
    :ok
  end

  # prune deletes entries in the cache, starting with the least-recently-used, until the cache bytes is within max_bytes.
  @spec prune(%CacheData{}) :: %CacheData{}
  defp prune(data) do
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

  @spec handle_call({:get, String.t}, any, %CacheData{}) :: {:reply, {:ok, Response} | :error, %CacheData{}}
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

  @spec handle_cast({:set, String.t}, Response) :: {:noreply, %CacheData{}}
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

  @spec handle_cast({:delete, String.t}, Response) :: {:noreply, %CacheData{}}
  def handle_cast({:delete, url}, data) do
    [{_, lru_index, val}] = :ets.lookup(data.table, url)
    :ets.delete(data.lru_table, lru_index)
    :ets.delete(data.table, url)
    val_bytes = byte_size val.body
    data = Map.put data, :bytes, data.bytes - val_bytes
    {:noreply, data}
  end

  # fetch gets the given URL from the cache, using all cache control mechanisms.
  # It's assumed the CacheManager is a singleton worker with the package name as the process name
  # If the URL is already in the cache, and hasn't expired, it's returned from cache.
  # If the URL is not in the cache, or has expired, it's requested from its origin, and stored in the cache
  @spec fetch(map, String.t) :: {atom, integer, map, binary}
  def fetch(request_headers_list, url) do
    case get CacheManager, url do
      {:ok, resp} ->
        IO.puts "found in cache " <> url
        req_headers = RequestManager.headers_to_map(request_headers_list)
        # TODO: put in Response struct?
        resp_req_cache_control = CacheControl.parse(resp.request_headers)
        resp_cache_control = CacheControl.parse(resp.headers)

        case Rules.can_reuse_stored? req_headers, resp.headers, resp_req_cache_control, resp_cache_control, resp.request_headers, resp.request_time, resp.response_time do
          :must_revalidate ->
            IO.puts "revalidating cache " <> url
            origin_revalidate(url, resp)
          true ->
            IO.puts "using cached " <> url
            {:ok, resp.code, resp.headers, resp.body}
          false ->
            IO.puts "can't use cached " <> url
            origin_request(url, request_headers_list)
        end
      :error ->
        IO.puts "not found in cache " <> url
        origin_request(url, request_headers_list)
    end
  end

  @spec origin_request(String.t, [{String.t, String.t}]) :: {:ok, integer, map, binary}
  defp origin_request(url, request_headers_list) do
    IO.puts "getting from origin `" <> url <> "`"
    # TODO: fix query params

    resp = RequestManager.request(url, request_headers_list)
    cache(url, resp)
    {:ok, resp.code, resp.headers, resp.body}
  end

  @spec origin_revalidate(String.t, Response) :: {:ok, integer, map, binary}
  defp origin_revalidate(url, old_response) do
    IO.puts "revalidating from origin `" <> url <> "`"
    resp = RequestManager.revalidate(url, old_response)
    if cache url, resp do
      IO.puts "cached revalidated `" <> url <> "`"
    else
      IO.puts "revalidate can't cache, deleting old cached `" <> url <> "`"
      # TODO: determine if this should be serialised with cache(), to avoid race deleting a newly cached val
      delete(Emissary.CacheManager, url)
    end
    {:ok, resp.code, resp.headers, resp.body}
  end

  @spec cache(String.t, Response) :: boolean
  defp cache(url, resp) do
    if Rules.can_cache? resp.request_headers, resp.code, resp.headers do
      req_cache_control = CacheControl.parse(resp.request_headers)
      IO.puts("cache_control:")
      IO.inspect(req_cache_control)
      IO.puts "caching " <> url
      set(Emissary.CacheManager, url, resp)
      true
    else
      IO.puts "can't cache " <> url
      false
    end
  end
end
