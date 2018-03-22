# Rihanna

Rihanna is a postgres-backed job distributed job queue for Elixir.

There is also a [beautiful UI](https://github.com/samphilipd/rihanna_ui)!

## Installation

1. Add `rihanna` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rihanna, ">= 0.0.0"}
  ]
end
```

2. Install with `mix deps.get`.

3. Run `mix ecto.gen.migration create_rihanna_jobs` and make your migration look like this:

```elixir
  require Rihanna.Migration

  def change do
    Rihanna.Migration.change()
  end
```

#### CONFIG STYLE 1

Add the full repo config to your `config.exs`

```elixir
config :rihanna, Rihanna.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "rihanna_db",
  hostname: "127.0.0.1",
  port: 5432
```

Add `Rihanna.Supervisor` to your supervision tree:

```elixir
children = [
  {Rihanna.Supervisor, [name: Rihanna.Supervisor]}
]
```

#### CONFIG STYLE 2

Add a minimal repo config to your `config.exs`

```elixir
config :rihanna, Rihanna.Repo,
  adapter: Ecto.Adapters.Postgres
```

Pass the database configuration in when you start `Rihanna.Supervisor`:

```elixir
children = [
  {Rihanna.Supervisor, [name: Rihanna.Supervisor, config: Your.Repo.config()]}
]
```

## FAQs

Q. Why Rihanna?

A. Because she knows how to [work, work, work, work, work](https://youtu.be/HL1UzIK-flA?t=18s).

