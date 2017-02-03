defmodule Emissary.Rules do


  @codes MapSet.new(
    [
      200, 201, 202, 203, 204, 205, 206, 207, 208, 226,
      300, 301, 302, 303, 304, 305, 306, 307, 308,
      400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 421, 422, 423, 424, 428, 429, 431, 451,
      500, 501, 502, 503, 504, 505, 506, 507, 508, 510, 511
      # \todo add unofficial (e.g. Nginx, Cloudflare) codes?
    ])

  # code_understood? returns whether the given response code is understood by this cache. Required by RFC7234§3
  def code_understood?(code) do
      MapSet.member?(@codes, code)
  end

    # \todo change to take Respons?
  def can_cache?(req_headers, resp_code, resp_headers, resp_body) do
    code_understood?(resp_code)
    && !Map.has_key?(req_headers, "no-store")
    && !Map.has_key?(resp_headers, "no-store")
    && !Map.has_key?(resp_headers, "private")
  end


end

