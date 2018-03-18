defmodule Sombrero.MixProject do
  use Mix.Project

  def project do
    [
      app: :sombrero,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
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
      {:ecto, "~> 2.2.9"},
      {:postgrex, "~> 0.13.3"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp package() do
    [
      description: "Sombrero is a database-backed job queue.",
      licenses: ["MIT"],
      maintainers: ["sampdavies@gmail.com"],
      links: %{}
    ]
  end
end
