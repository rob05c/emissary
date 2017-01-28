defmodule Cowboy.RootPageHandler do
  def init(_transport, req, []) do
    {:ok, req, nil}
  end

  def add_query_string(qs) do
    if qs == "" do
      ""
    else
      "?" <> qs
    end
  end

  def handle(req, state) do
    {path, _} = :cowboy_req.path(req)
    {qs, _} = :cowboy_req.qs(req)

    replyStr = "You requested " <> path <> add_query_string(qs) <> "\r\n"
    {:ok, req} = :cowboy_req.chunked_reply(200, req)
    :ok = :cowboy_req.chunk(replyStr, req)
    {:ok, req, state}
  end

  def terminate(_reason, _req, _state) do
    :ok
  end
end
