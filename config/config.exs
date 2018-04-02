use Mix.Config

config :rihanna,
  jobs_table_name: "rihanna_jobs",
  postgrex: [
    username: "sam",
    password: "",
    database: "rihanna_db",
    hostname: "127.0.0.1",
    port: 5432
  ]
