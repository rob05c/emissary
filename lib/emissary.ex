defmodule Emissary do
  use Application
  alias Emissary.RemapManager, as: RemapManager
  alias Emissary.CacheManager, as: CacheManager
  alias Emissary.RequestManager, as: RequestManager
  @cache_max_bytes 1_000_000_000
  @port 8080
  # TODO: add follow-redirects config

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  @spec start(any, any) :: Supervisor.on_start
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      Plug.Adapters.Cowboy.child_spec(:http, EmissaryRouter, [], [port: @port]),
      worker(RemapManager, [RemapManager]),
      worker(CacheManager, [CacheManager, @cache_max_bytes]),
      worker(RequestManager, [RequestManager])
      # Starts a worker by calling: Emissary.Worker.start_link(arg1, arg2, arg3)
      # worker(Emissary.Worker, [arg1, arg2, arg3]),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Emissary.Supervisor]
    Supervisor.start_link(children, opts)
  end

end
