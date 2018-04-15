defmodule Rihanna.MixProject do
  use Mix.Project

  def project do
    [
      app: :rihanna,
      version: "0.5.1",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: [
        main: "Rihanna",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:postgrex, "~> 0.13.3"},
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
      links: %{}
    ]
  end
end
