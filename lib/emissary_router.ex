defmodule EmissaryRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  @spec add_qs(String.t) :: String.t
  defp add_qs(qs) do
    if qs == "" do
      ""
    else
      "?" <> qs
    end
  end

  @spec domain_to_remap(Plug.Conn) :: String.t
  defp domain_to_remap(conn) do
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
        |> put_resp_header("content-length", Integer.to_string(byte_size(body)))
        |> delete_resp_header("max-age")
        |> delete_resp_header("cache-control")

        # TODO: figure out how to delete server,date,content-length from Plug/Cowboy, and stop downcasing cached headers

        headers
        |> Enum.reduce(conn, fn({k, v}, conn) ->
          header = String.downcase(k)
          # TODO: make this generic?
          if header != "transfer-encoding" do
            put_resp_header(conn, header, v)
          else
            conn
          end
        end)
        |> send_resp(code, body)
      _ ->
        IO.puts "requested domain not found, returning 404 " <> request_domain
        send_resp(conn, 404, "not found")
    end
  end
end
