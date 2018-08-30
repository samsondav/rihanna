# Contributing

PRs are welcome, please feel free to tackle an issue that already exists and reference the issue in your PR description.

> What if I found a new bug or would like a new feature?

Please first create an issue for it, then feel free to submit a PR for it.

We ask that you add tests for your changes.

## Getting the test suite running

If you have a custom setup for your Postgres setup (e.g. running on a different port to 5432) you may need to add some extra config so Rihanna can see it.

To do this, add a local.exs config file with your changes to the config.

You can use the config.exs file as a template for what might go in there.

Next, you'll need a database for Rihanna to store its jobs in.

If you were using psql to interact with your database:

```
-> psql
sql (10.5, server 9.6.10)
Type "help" for help.

(ins)username=# create database rihanna_db;
CREATE DATABASE
```

Next, you need to migrate your database to have the right table in it where Rihanna stores its jobs.

To do this, you can take the sql from the helpers provided for migrations.

```
-> iex -S mix
Erlang/OTP 21 [erts-10.0.4] [source] [64-bit] [smp:4:4] [ds:4:4:10] [async-threads:1] [hipe]

Interactive Elixir (1.7.1) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> IO.puts Rihanna.Migration.sql
CREATE TABLE rihanna_jobs (
... more sql ...
ALTER TABLE ONLY rihanna_jobs
ADD CONSTRAINT rihanna_jobs_pkey PRIMARY KEY (id);

:ok
```

Then you can copy and paste that sql into your psql session from before.

After that you should be good to `mix test`.
