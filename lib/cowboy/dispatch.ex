defmodule Cowboy.Dispatch do
  def start do
    dispatch = :cowboy_router.compile([
      { :_,
        [
          {"/", Cowboy.RootPageHandler, []},
          {"/[...]", Cowboy.RootPageHandler, []},
          # serves files in /priv
          # {"/[...]", :cowboy_static, { :priv_dir, :emissary, "",[{:mimetypes,:cow_mimetypes,:all}]}}
        ]
      }
    ])
    {:ok, _} = :cowboy.start_http(:emissary, 100, [{:port, 8080}],[{:env, [{:dispatch, dispatch}]}])
  end
end
