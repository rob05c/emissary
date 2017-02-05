# Emissary

HTTP caching proxy in [Elixir](http://elixir-lang.org) using [Plug](https://github.com/elixir-lang/plug)/[Cowboy](https://github.com/ninenines/cowboy) to serve and [HTTPoison](https://github.com/edgurgel/httpoison) for origin requests.

Proxies requests for FQDNs, using a `remap.config` file in [ATS](https://docs.trafficserver.apache.org/en/latest/admin-guide/files/remap.config.en.html) format. Requests are cached up to a `max_bytes` variable, after which least-recently-used URLs are purged from the cache. Implements [HTTP/1.1 RFC 7234](https://tools.ietf.org/html/rfc7234) caching.

## Installation

Install [Elixir](http://elixir-lang.org/install.html), minimum version 1.3.4

Get the code
```
$ git clone https://github.com/rob05c/emissary
```

Get the dependencies

```
$ cd emissary

$ mix deps.get
```

Add a remap rule
```
$ echo "remap http://localhost http://example.net" >> remap.config
```

Run the service

```
$ iex -S mix
```

Test (in another terminal)

```
curl -v "http://localhost:8080/"
```

## Configuration

Currently, all configuration is done at compile time, in the source code. Configuration variables are at the top of `lib/emissary.ex`.

`@cache_max_bytes` - the maximum bytes to cache from response bodies.
* Currently only the body is considered, so for many small-bodied results, significantly more memory may be used storing headers.

`@port` - the port to serve on
