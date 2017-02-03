# Emissary

HTTP caching proxy in Elixir using Plug/Cowboy.

The service transparently proxies requests for FQDNs, using a `remap.config` file in [ATS](https://docs.trafficserver.apache.org/en/latest/admin-guide/files/remap.config.en.html) format. Requests are cached up to a max_bytes variable, after which least-recently-used URLs are purged from the cache.

The intention is to implement [HTTP/1.1](https://tools.ietf.org/html/rfc7234) caching, but its rules are not yet implemented.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `emissary` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:emissary, "~> 0.1.0"}]
    end
    ```

  2. Ensure `emissary` is started before your application:

    ```elixir
    def application do
      [applications: [:emissary]]
    end
    ```

