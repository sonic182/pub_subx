defmodule PubSubx.MixProject do
  use Mix.Project

  def project do
    [
      app: :pub_subx,
      version: "0.2.3",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      description:
        "A lightweight and efficient PubSub library for Elixir, built on top of GenServer and Registry, providing robust pubsub functionalities for real-time messaging and event handling.",
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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
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
        "A lightweight and efficient PubSub library for Elixir, built on top of GenServer and Registry, providing robust pubsub functionalities for real-time messaging and event handling."
    ]
  end
end
