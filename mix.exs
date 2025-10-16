defmodule Litmus.MixProject do
  use Mix.Project

  def project do
    [
      app: :litmus,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir wrapper for the PURITY static analyzer for purity analysis",
      package: package(),
      docs: docs(),
      # Enable debug_info for proper BEAM analysis
      erlc_options: [:debug_info],
      # Include Erlang source paths
      erlc_paths: ["src"],
      compilers: [:erlang, :elixir, :app],
      # Suppress xref warnings for PURITY internal modules
      xref: [exclude: [:purity_collect]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :purity]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # PURITY static analyzer - Erlang library (local source with fixes)
      {:purity, path: "purity_source", manager: :rebar3, override: true, compile: "make"},
      # JSON encoder/decoder
      {:jason, "~> 1.4"},
      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "litmus",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/yourusername/litmus",
        "PURITY" => "https://github.com/mpitid/purity"
      }
    ]
  end

  defp docs do
    [
      main: "Litmus",
      extras: ["README.md"]
    ]
  end
end
