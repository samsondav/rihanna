defmodule Rihanna.MixProject do
  use Mix.Project

  def project do
    [
      app: :rihanna,
      version: "2.3.0",
      elixir: "~> 1.6",
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
    case Mix.env() do
      # In test we start an application to test the Ecto Repo integration
      :test ->
        [
          mod: {TestApp, []},
          extra_applications: [:logger, :runtime_tools]
        ]

      _ ->
        [extra_applications: [:logger]]
    end
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:postgrex, ">= 0.13.3"},
      {:telemetry, "~> 0.2"},
      # Optional Ecto integration
      {:ecto, ">= 2.0.0", optional: true},
      {:ecto_sql, ">= 3.0.0", optional: true},
      # Development tools
      {:jason, ">= 1.1.2", only: :test},
      {:benchee, ">= 0.13.0", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:mix_test_watch, ">= 0.0.0", only: :dev, runtime: false},
      {:temporary_env, ">= 2.0.0", only: :test, runtime: false}
    ]
  end

  defp package() do
    [
      description: "Rihanna is a database-backed job queue.",
      licenses: ["MIT"],
      maintainers: ["sampdavies@gmail.com", "louis@lpil.uk"],
      links: %{"GitHub" => "https://github.com/samphilipd/rihanna"}
    ]
  end
end
