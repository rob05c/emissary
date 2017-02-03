defmodule Emissary.Rules do


  @codes MapSet.new(
    [
      200, 201, 202, 203, 204, 205, 206, 207, 208, 226,
      300, 301, 302, 303, 304, 305, 306, 307, 308,
      400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 421, 422, 423, 424, 428, 429, 431, 451,
      500, 501, 502, 503, 504, 505, 506, 507, 508, 510, 511
      # \todo add unofficial (e.g. Nginx, Cloudflare) codes?
    ])

  @default_cacheable_response_codes MapSet.new([200, 203, 204, 206, 300, 301, 404, 405, 410, 414, 501])

  # code_understood? returns whether the given response code is understood by this cache. Required by RFC7234§3
  def code_understood?(code) do
      MapSet.member?(@codes, code)
  end

  # \todo change to take Response?
  def can_cache?(req_headers, resp_code, resp_headers, resp_body) do
    req_cache_control = Emissary.CacheControl.parse(req_headers)
    resp_cache_control = Emissary.CacheControl.parse(resp_headers)
    can_store_response?(req_headers, resp_code, resp_headers, resp_body, req_cache_control, resp_cache_control)
    # \todo implement RFC7234§3.1 incomplete response storage
    && can_store_authenticated?(req_headers, resp_code, resp_headers, resp_body, req_cache_control, resp_cache_control)


  end

  # can_store_response? checks the constraints in RFC7234§3.2
  # \todo ensure RFC7234§3.2 requirements that max-age=0, must-revlaidate, s-maxage=0 are revalidated
  def can_store_authenticated?(req_headers, resp_code, resp_headers, resp_body, req_cache_control, resp_cache_control) do
    !Map.has_key?(req_cache_control,     "authorization")
    || Map.has_key?(resp_cache_control,  "must-revalidate")
    || Map.has_key?(resp_cache_control,  "public")
    || Map.has_key?(resp_cache_control,  "s-maxage")
  end

  # can_store_response? checks the constraints in RFC7234§3
  def can_store_response?(req_headers, resp_code, resp_headers, resp_body, req_cache_control, resp_cache_control) do
    code_understood?(resp_code)
    && !Map.has_key?(req_cache_control,  "no-store")
    && !Map.has_key?(resp_cache_control, "no-store")
    && !Map.has_key?(resp_cache_control, "private")
    && !Map.has_key?(resp_headers, "authorization")
    && cache_control_allows?(resp_code, resp_headers, resp_cache_control)
  end

  def cache_control_allows?(resp_code, resp_headers, resp_cache_control) do
    Map.has_key?(resp_headers,  "expires")
    || Map.has_key?(resp_cache_control,  "max-age")
    || Map.has_key?(resp_cache_control,  "s-max-age")
    || extension_allows?(resp_cache_control)
    || code_default_cacheable?(resp_code)
  end

  # extension_allows? returns whether a cache-control extension allows the response to be cached, per RFC7234§3 and RFC7234§5.2.3. Note this currently fulfills the literal wording of the section, but cache-control extensions may override any requirements, in which case the logic of can_cache? outside this function would have to be changed.
  def extension_allows?(resp_cache_control) do
    false
  end

  def code_default_cacheable?(resp_code) do
      MapSet.member?(@default_cacheable_response_codes, resp_code)
  end

  # can_reuse_stored? checks the constraints in RFC7234§4
  def can_reuse_stored?(req_headers, resp_code, resp_headers, resp_body, req_cache_control, resp_cache_control, resp_req_headers) do
    selected_headers_match?(req_headers, resp_req_headers)
    && !has_pragma_no_cache?(req_headers)
    && !Map.has_key? req_cache_control, "no-cache"
    && (validated?(resp_body) || (!Map.has_key?(req_cache_control, "no-cache") && !Map.has_key?(resp_cache_control, "no-cache")))
    && (fresh?(resp_body) || allowed_stale?(resp_body) || validated?(resp_body))
  end

  # fresh? checks the constraints in RFC7234§4 via RFC7234§4.2
  def fresh?(resp_body) do

  end

  # allowed_stale? checks the constraints in RFC7234§4 via RFC7234§4.2.4
  def allowed_stale?(resp_body) do

  end

  # validated? checks the constraints in RFC7234§4 via RFC7234§4.3
  def validated?(resp_body) do

  end

  # "Vary: accept-encoding, accept-language"
  # selected_headers_match? checks the constraints in RFC7234§4.1
  # \todo change caching to key on URL+headers, so multiple requests for the same URL with different vary headers can be cached?
  def selected_headers_match?(req_headers, resp_req_headers) do
    case Map.fetch(req_headers,  "vary") do
      {:ok, vary_header} ->
        if vary_header == "*" do
          false
        else
          # \todo extract method?
          vary_header = String.downcase(vary_header)
          vary_fields = String.split(vary_header, ",")
          Enum.all? vary_fields, fn(field) ->
            Map.has_key? resp_req_headers, field
          end
        end
      _ ->
        true
    end
  end

  # has_pragma_no_cache? returns whether the given headers have a `pragma: no-cache` which is to be considered per HTTP/1.1. This specifically returns false if `cache-control` exists, even if `pragma: no-cache` exists, per RFC7234§5.4
  def has_pragma_no_cache?(req_headers) do
    !Map.has_key? req_headers, "cache-control"
    && Map.has_key?(req_headers, "pragma")
    && String.starts_with?(Map.fetch!(req_headers, "pragma"), "no-cache")
  end
end

