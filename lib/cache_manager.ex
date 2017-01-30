defmodule Emissary.CacheManager do
  use GenServer

  # \todo change to use Erlang Term Storage
  defmodule CacheData do
    @enforce_keys [:max_bytes]
    defstruct cache: %{}, bytes: 0, max_bytes: 0
  end

  def start_link(name, max_bytes) do
    GenServer.start_link __MODULE__, max_bytes, name: name
  end

  def get(server, url) do
    GenServer.call server, {:get, url}
  end

  # \todo change val from a string to a struct containing headers etc
  def set(server, url, val) do
    GenServer.cast server, {:set, url, val}
  end

  def init(max_bytes) do
    data = %CacheData{max_bytes: max_bytes}
    {:ok, data}
  end

  def handle_call({:get, url}, _from, data) do
    cache = data.cache
    val = Map.fetch cache, url
    {:reply, val, data}
  end

  def handle_cast({:set, url, val}, data) do
    cache = Map.put data.cache, url, val
    data = Map.put data, :cache, cache
    val_bytes = byte_size val
    data = Map.put data, :bytes, val_bytes
    # \todo delete entries that exceed the cache limit
    {:noreply, data}
  end

  # fetch gets the given URL from the cache, using all cache control mechanisms.
  # It's assumed the CacheManager is a singleton worker with the package name as the process name
  # If the URL is already in the cache, and hasn't expired, it's returned from cache.
  # If the URL is not in the cache, or has expired, it's requested from its origin, and stored in the cache
  def fetch(url) do
    case Emissary.CacheManager.get Emissary.CacheManager, url do
      {:ok, val} ->
        IO.puts "found in cache " <> url
        {:ok, 200, val} # \todo handle expired entries
      :error ->
        # \todo extract method?
        # \todo request in serial, so we don't flood an origin if a million requests come in at once.
        IO.puts "not found in cache, getting from origin " <> url
        # \todo fix query params
        case HTTPoison.get(url, [], []) do
          {:ok, response} ->
            IO.puts "caching " <> url
            # \todo cache headers, code
            Emissary.CacheManager.set(Emissary.CacheManager, url, response.body)
            {:ok, 200, response.body}
          {:error, err} ->
            IO.puts "origin failed with " <> HTTPoison.Error.message(err)
            {:ok, 500, "origin server error"} # \todo change to generic 500
          _ -> # should never happen
            IO.puts "origin returned unknown value"
            # \todo put in cache, so we don't continuously hit dead origins?
            {:ok, 500, "internal server error"}
        end
    end
  end
end
