use Mix.Config

if System.get_env("TRAVIS") == "true" do
  config :rihanna,
    jobs_table_name: "rihanna_jobs",
    postgrex: [
      username: "postgres",
      password: "",
      database: "rihanna_test_db",
      hostname: "127.0.0.1",
      port: 5432
    ]
else
  config :rihanna,
    jobs_table_name: "rihanna_jobs",
    postgrex: [
      username: "sam",
      password: "",
      database: "rihanna_db",
      hostname: "127.0.0.1",
      port: 5432
    ]
end
