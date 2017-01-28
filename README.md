# Emissary

HTTP server in Elixir using Cowboy.

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

