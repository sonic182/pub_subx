defmodule PubSubx.MixProject do
  use Mix.Project

  def project do
    [
      app: :pub_subx,
      version: "1.0.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      description:
        "A lightweight event router for Elixir with hierarchical topics, filtering, and observable delivery.",
      test_coverage: [tool: ExCoveralls],
      package: package(),
      deps: deps(),
      aliases: aliases(),
      docs: [
        main: "PubSubx",
        extras: ["README.md", "CHANGELOG.md"],
        groups_for_extras: [
          guides: ~w(README.md CHANGELOG.md)
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 1.0"},
      {:benchee, "~> 1.3", only: :dev, runtime: false},
      {:phoenix_pubsub, "~> 2.1", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.5", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "cmd env MIX_ENV=test mix test"
      ]
    ]
  end

  defp package do
    [
      maintainers: ["sonic182"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/sonic182/pub_subx"},
      description:
        "A lightweight event router for Elixir with hierarchical topics, filtering, and observable delivery."
    ]
  end
end
