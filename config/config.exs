use Mix.Config

config :rihanna,
  jobs_table_name: "rihanna_jobs",
  postgrex: [
    username: "postgres",
    password: "",
    database: "rihanna_test_db",
    hostname: "127.0.0.1",
    port: 5432
  ]

if File.exists?("config/local.exs") do
  import_config "local.exs"
end
