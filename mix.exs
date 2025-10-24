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
      # Compile test support modules
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:erlang, :elixir, :app],
      # Suppress xref warnings for PURITY internal modules
      xref: [exclude: [:purity_collect, :purity_analyse]],
      # Dialyzer configuration
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore_warnings",
        plt_add_apps: [:purity, :mix, :iex, :eex],
        paths: ["_build/dev/lib/litmus/ebin", "purity_source/ebin"]
      ],
      # Test coverage configuration
      test_coverage: [tool: ExCoveralls],
      # Preferred CLI environment for coveralls tasks
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support", "spike3"]
  defp elixirc_paths(_), do: ["lib"]

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
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      # Static type checker
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      # Code coverage
      {:excoveralls, "~> 0.18", only: :test},
      # Property-based testing
      {:stream_data, "~> 1.0", only: :test}
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
