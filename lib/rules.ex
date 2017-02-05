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
  def can_cache?(req_headers, resp_code, resp_headers) do
    req_cache_control = Emissary.CacheControl.parse(req_headers)
    resp_cache_control = Emissary.CacheControl.parse(resp_headers)
    can_store_response?(resp_code, resp_headers, req_cache_control, resp_cache_control)
    # \todo implement RFC7234§3.1 incomplete response storage
    && can_store_authenticated?(req_cache_control, resp_cache_control)
  end

  # can_store_response? checks the constraints in RFC7234§3.2
  # \todo ensure RFC7234§3.2 requirements that max-age=0, must-revlaidate, s-maxage=0 are revalidated
  def can_store_authenticated?(req_cache_control, resp_cache_control) do
    !Map.has_key?(req_cache_control,     "authorization")
    || Map.has_key?(resp_cache_control,  "must-revalidate")
    || Map.has_key?(resp_cache_control,  "public")
    || Map.has_key?(resp_cache_control,  "s-maxage")
  end

  # can_store_response? checks the constraints in RFC7234
  def can_store_response?(resp_code, resp_headers, req_cache_control, resp_cache_control) do
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
    || extension_allows?()
    || code_default_cacheable?(resp_code)
  end

  # extension_allows? returns whether a cache-control extension allows the response to be cached, per RFC7234§3 and RFC7234§5.2.3. Note this currently fulfills the literal wording of the section, but cache-control extensions may override any requirements, in which case the logic of can_cache? outside this function would have to be changed.
  def extension_allows?() do
    false
  end

  def code_default_cacheable?(resp_code) do
      MapSet.member?(@default_cacheable_response_codes, resp_code)
  end

  # can_reuse_stored? checks the constraints in RFC7234§4
  # returns true if the cached repsonse can be reused, false if it cannot, and :must_revalidate if it can be reused upon successful validation.
  def can_reuse_stored?(req_headers, resp_headers, req_cache_control, resp_cache_control, resp_req_headers, resp_req_time, resp_resp_time) do
    # TODO: remove allowed_stale, check in cache manager after revalidate fails? (since RFC7234§4.2.4 prohibits serving stale response unless disconnected).
    cond do
      !selected_headers_match?(req_headers, resp_req_headers) ->
        # TODO: implement caching the same url multiple times for different selected (Vary) headers
        IO.puts "can_reuse_stored? no - selected headers don't match"
        false
      !fresh?(resp_headers, resp_cache_control, resp_req_time, resp_resp_time) && !allowed_stale?(resp_headers, req_cache_control, resp_cache_control, resp_req_time, resp_resp_time) ->
        IO.puts "can_reuse_stored? :must_revalidate - not fresh, and not allowed stale"
        :must_revalidate
      has_pragma_no_cache?(req_headers) ->
        IO.puts "can_reuse_stored? :must_revalidate - has pragma no-cache"
        :must_revalidate
      Map.has_key?(req_cache_control, "no-cache") ->
        IO.puts "can_reuse_stored? :must_revalidate - request has cache-control no-cache"
        :must_revalidate
      Map.has_key?(resp_cache_control, "no-cache") ->
        IO.puts "can_reuse_stored? :must_revalidate - response has cache-control no-cache"
        :must_revalidate
      true ->
        IO.puts "can_reuse_stored? yes"
        true
    end
  end

  # fresh? checks the constraints in RFC7234§4 via RFC7234§4.2
  def fresh?(resp_headers, resp_cache_control, resp_req_time, resp_resp_time) do
    freshness_lifetime = get_freshness_lifetime(resp_headers, resp_cache_control)
    current_age = get_current_age(resp_headers, resp_req_time, resp_resp_time)
    freshness_lifetime > current_age
  end

  def get_http_date(map, key) do
    case Map.fetch(map, key) do
      {:ok, http_date} ->
        parse_http_date(http_date)
      :error ->
        false
    end
  end

  # TODO: change to return {:ok}, so false doesn't make case matching fail if the 'false' isn't first.
  def get_http_delta_seconds(map, key) do
    case Map.fetch(map, key) do
      {:ok, seconds_str} ->
        case Integer.parse(seconds_str) do
          {seconds, _} ->
            seconds
          :error ->
            false
        end
      :error ->
        false
    end
  end

  # freshness_lifetime calculates the freshness_lifetime per RFC7234§4.2.1
  def get_freshness_lifetime(resp_headers, resp_cache_control) do
    get_s_maxage = fn() ->
      get_http_delta_seconds(resp_cache_control, "s-maxage")
    end

    get_maxage = fn() ->
      get_http_delta_seconds(resp_cache_control, "max-age")
    end

    get_expires = fn() ->
      with {:ok, expires} <- get_http_date(resp_headers, "expires"),
           {:ok, date} <- get_http_date(resp_headers, "date"),
            do: Timex.to_unix(expires) - Timex.to_unix(date)
    end

    get_heuristic = fn() ->
      heuristic_freshness(resp_headers)
    end

    freshness_fns = [get_s_maxage, get_maxage, get_expires, get_heuristic]
    Enum.find_value freshness_fns, false, fn(freshness_fn) ->
      freshness_fn.()
    end
  end

  @seconds_in_24_hours 60*60*24

  # heuristic_freshness follows the recommendation of RFC7234§4.2.2 and returns the min of 10% of the (Date - Last-Modified) headers and 24 hours, if they exist, and 24 hours if they don't.
  # TODO: smarter and configurable heuristics
  def heuristic_freshness(resp_headers) do
    case since_last_modified(resp_headers) do
      false ->
        @seconds_in_24_hours
      seconds ->
        min(@seconds_in_24_hours, seconds)
    end
  end

  # TODO combine with get_expires?
  def since_last_modified(headers) do
    with {:ok, last_modified} <- get_http_date(headers, "last-modified"),
         {:ok, date} <- get_http_date(headers, "date"),
      do: Timex.to_unix(date) - Timex.to_unix(last_modified)
  end

  # parse_http_date parses the given HTTP-date (RFC7231§7.1.1) and returns a DateTime or :invalid
  def parse_http_date(http_date) do
    imf_fixdate_format = "%a, %d %b %Y %H:%M:%S GMT"
    obsolete_rfc850_format = "%A, %d-%b-%y %H:M:S GMT"
    obsolete_asctime_format = "%a %b %e  %H:%M:%S %Y"
    formats = [imf_fixdate_format, obsolete_rfc850_format, obsolete_asctime_format]
    Enum.find_value formats, :invalid, fn(format) ->
      case Timex.parse(http_date, format, :strftime) do
        {:ok, datetime} ->
          {:ok, datetime}
        {:error, _} ->
          false
        naive_datetime ->
          # TODO: update to more efficient `DateTime.from_naive!(naive_datetime, "Etc/UTC")` in Elixir 1.4
          Elixir.Timex.Parse.DateTime.Parser.parse(NaiveDateTime.to_iso8601(naive_datetime), "{ISO:Extended:Z}")
      end
    end
  end

  # age_value is used to calculate current_age per RFC7234§4.2.3
  def age_value(resp_headers) do
    case get_http_delta_seconds(resp_headers, "age") do
      false ->
        0
      seconds ->
        seconds
    end
  end

  # date_value is used to calculate current_age per RFC7234§4.2.3. It returns integer UNIX seconds since the epoch, or :error if the response had no Date header (in violation of HTTP/1.1).
  def date_value(resp_headers) do
    case get_http_date(resp_headers, "date") do
      {:ok, date} ->
        Timex.to_unix(date)
      false ->
        :error
    end
  end

  # now is used to calculate current_age per RFC7234§4.2.3. Returns integer UNIX seconds since the epoch.
  def now() do
    Timex.to_unix(DateTime.utc_now())
  end

  def request_time(resp_req_time) do
    Timex.to_unix(resp_req_time)
  end

  def response_time(resp_resp_time) do
    Timex.to_unix(resp_resp_time)
  end

  def apparent_age(resp_headers, resp_resp_time) do
    max(0, response_time(resp_resp_time) - date_value(resp_headers))
  end

  def response_delay(resp_req_time, resp_resp_time) do
    response_time(resp_resp_time) - request_time(resp_req_time)
  end

  def corrected_age_value(resp_headers, resp_req_time, resp_resp_time) do
    age_value(resp_headers) + response_delay(resp_req_time, resp_resp_time)
  end

  # TODO: add config option to promise all caches in hop are HTTP/1.1, per RFC7234§4.2.3
  def corrected_initial_age(resp_headers, resp_req_time, resp_resp_time) do
    max(apparent_age(resp_headers, resp_resp_time), corrected_age_value(resp_headers, resp_req_time, resp_resp_time))
  end

  def resident_time(resp_resp_time) do
    now() - response_time(resp_resp_time)
  end

  def get_current_age(resp_headers, resp_req_time, resp_resp_time) do
    corrected_initial_age(resp_headers, resp_req_time, resp_resp_time)
  end


  # TODO: add min-fresh check

  # TODO: add warning generation funcs

  # allowed_stale? checks the constraints in RFC7234§4 via RFC7234§4.2.4
  def allowed_stale?(resp_headers, req_cache_control, resp_cache_control, resp_req_time, resp_resp_time) do
    (!Map.has_key?(req_cache_control, "max-age") || Map.has_key?(req_cache_control, "max-stale"))
    && !Map.has_key?(resp_cache_control, "must-revalidate")
    && !Map.has_key?(resp_cache_control, "no-cache")
    && !Map.has_key?(resp_cache_control, "no-store")
    && in_max_stale?(resp_headers, resp_cache_control, resp_req_time, resp_resp_time)
  end

  # in_max_stale? returns whether the given response is within the `max-stale` request directive. If no `max-stale` directive exists in the request, `true` is returned.
  def in_max_stale?(resp_headers, resp_cache_control, resp_req_time, resp_resp_time) do
    case get_http_delta_seconds(resp_cache_control, "max-stale") do
      false ->
        true # if there's no max-stale, return true
      seconds ->
        freshness_lifetime = get_freshness_lifetime(resp_headers, resp_cache_control)
        current_age = get_current_age(resp_headers, resp_req_time, resp_resp_time)
        seconds > (current_age - freshness_lifetime)
    end
  end

  # # validated? checks the constraints in RFC7234§4 via RFC7234§4.3
  # def validated?(resp_body) do

  # end

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
          vary_header
          |> String.downcase
          |> String.split(",")
          |> Enum.all?(fn(field) ->
            Map.has_key? resp_req_headers, field
          end)
        end
      _ ->
        true
    end
  end

  # has_pragma_no_cache? returns whether the given headers have a `pragma: no-cache` which is to be considered per HTTP/1.1. This specifically returns false if `cache-control` exists, even if `pragma: no-cache` exists, per RFC7234§5.4
  def has_pragma_no_cache?(req_headers) do
    !Map.has_key?(req_headers, "cache-control")
    && Map.has_key?(req_headers, "pragma")
    && String.starts_with?(Map.fetch!(req_headers, "pragma"), "no-cache")
  end
end
