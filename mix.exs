defmodule Rihanna.MixProject do
  use Mix.Project

  def project do
    [
      app: :rihanna,
      version: "1.0.1",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [ignore_warnings: "dialyzer.ignore-warnings"],
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: [
        main: "Rihanna",
        extras: ["README.md"]
      ],
      # Docs
      name: "Rihanna",
      source_url: "https://github.com/samphilipd/rihanna",
      homepage_url: "https://github.com/samphilipd/rihanna/README.md"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:postgrex, ">= 0.13.3"},
      # Development tools
      {:benchee, ">= 0.13.0", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:mix_test_watch, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package() do
    [
      description: "Rihanna is a database-backed job queue.",
      licenses: ["MIT"],
      maintainers: ["sampdavies@gmail.com"],
      links: %{"GitHub" => "https://github.com/samphilipd/rihanna"}
    ]
  end
end
