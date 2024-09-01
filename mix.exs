defmodule PubSubx.MixProject do
  use Mix.Project

  def project do
    [
      app: :pub_subx,
      version: "0.2.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      description: "A lightweight PubSub library built on top of GenServer and Registry.",
      package: package(),
      deps: deps(),
      docs: [
        main: "PubSubx",
        extras: ["README.md", "CHANGELOG.md"]
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
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["sonic182"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/sonic182/pub_subx"}
    ]
  end
end
