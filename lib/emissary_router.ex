defmodule EmissaryRouter do
  use Plug.Router

  plug :match
  plug :dispatch

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
    request_headers = conn.req_headers

    case Emissary.RemapManager.get(Emissary.RemapManager, request_domain) do
      {:ok, remapped_domain} ->
        remapped_url = remapped_domain <> conn.request_path <> add_qs(conn.query_string)

        IO.puts "getting " <> remapped_url
        {:ok, code, headers, body} = Emissary.CacheManager.fetch(request_headers, remapped_url)

        conn = conn
        |> put_resp_header("server", "")
        |> put_resp_header("date", "")
        |> put_resp_header("content-length", "")
        |> delete_resp_header("max-age")
        |> delete_resp_header("cache-control")

        # \todo figure out how to delete server,date,content-length from Plug/Cowboy, and stop downcasing cached headers

        headers
        |> Enum.reduce(conn, fn({k, v}, conn) ->
          put_resp_header(conn, String.downcase(k), v)
        end)
        |> send_resp(code, body)
      _ ->
        IO.puts "requested domain not found, returning 404 " <> request_domain
        send_resp(conn, 404, "not found")
    end
  end
end
