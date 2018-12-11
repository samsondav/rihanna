use Mix.Config

postgrex_config = [
  username: "postgres",
  password: "",
  database: "rihanna_db",
  hostname: "127.0.0.1",
  port: 5432
]

config :rihanna,
  jobs_table_name: "rihanna_jobs",
  postgrex: postgrex_config,
  debug: true

# config :logger, level: :debug
config :logger, level: :warn

if Mix.env() == :test do
  config :rihanna, ecto_repos: [TestApp.Repo]
  config :rihanna, TestApp.Repo, postgrex_config
end

if File.exists?("config/local.exs") do
  import_config "local.exs"
end
