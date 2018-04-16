use Mix.Config

config :rihanna,
  jobs_table_name: "rihanna_jobs",
  postgrex: [
    username: "postgres",
    password: "",
    database: "rihanna_db",
    hostname: "127.0.0.1",
    port: 5432
  ],
  debug: true

config :logger, level: :debug

if File.exists?("config/local.exs") do
  import_config "local.exs"
end
