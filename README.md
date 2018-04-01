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

3. Add a migration to create your jobs table

Rihanna stores jobs in a table in your database. By default this is called "rihanna_jobs".

Run `mix ecto.gen.migration create_rihanna_jobs` and make your migration look like this:

```elixir
defmodule MyApp.CreateRihannaJobs do
  use Rihanna.Migration
end
```

4. Add `Rihanna.Supervisor` to your supervision tree

`Rihanna.Supervisor` starts a job dispatcher and by adding it to your supervision tree it will automatically start running jobs when your app boots.

Rihanna requires a database configuration to be passed in under the `postgrex` key. This is passed through directly to Postgrex.

If you are already using Ecto you can avoid duplicating your DB config by pulling this out of your existing Repo using `My.Repo.config()`.

```elixir
# NOTE: In Phoenix you would find this inside `lib/my_app/application.ex`
children = [
  {Rihanna.Supervisor, [name: Rihanna.Supervisor, postgrex: My.Repo.config()]}
]
```

## Usage

TODO: Write this

## Configuration

Rihanna should work out of the box without any configuration. However, should you
wish to tweak it, take a look at the documentation for [Rihanna.Config](insert_documentation_here).

## FAQs

Q. Why Rihanna?

A. Because she knows how to [work, work, work, work, work](https://youtu.be/HL1UzIK-flA?t=18s).

