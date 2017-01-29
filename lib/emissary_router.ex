defmodule EmissaryRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/hello" do
    send_resp(conn, 200, "world")
  end

  def add_qs(qs) do
    if qs == "" do
      ""
    else
      "?" <> qs
    end
  end

  match _ do
    {:ok, rule} = Emissary.RemapManager.lookup(Emissary.RemapManager, "http://foo.localhost")
    s = "foo.localhost map: " <> rule <> "\r\n"
    # s = "You're at " <> conn.request_path <> add_qs(conn.query_string)
    send_resp(conn, 200, s)
  end
end
