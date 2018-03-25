use Mix.Config

# Has to match whatever is in test_helper
config :rihanna,
  jobs_table_name: "rihanna_jobs",
  postgrex: [
    username: "sam",
    password: "",
    database: "rihanna_db",
    hostname: "127.0.0.1",
    port: 5432
  ]
