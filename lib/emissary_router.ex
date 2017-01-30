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

  def domain_to_remap(conn) do
    Atom.to_string(conn.scheme) <> "://" <> conn.host
  end

  match _ do
    request_domain = domain_to_remap(conn)

    case Emissary.RemapManager.get(Emissary.RemapManager, request_domain) do
      {:ok, remapped_domain} ->
        remapped_url = remapped_domain <> conn.request_path <> add_qs(conn.query_string) <> "\r\n"

        IO.puts "getting " <> remapped_url
        {:ok, code, body} = Emissary.CacheManager.fetch(remapped_url)
        send_resp(conn, code, body)
      _ ->
        IO.puts "requested domain not found, returning 404 " <> request_domain
        send_resp(conn, 404, "not found")
    end
  end
end
