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
    s = "You're at " <> conn.request_path <> add_qs(conn.query_string)
    send_resp(conn, 200, s)
  end
end
