# Rihanna

Rihanna is a fast, reliable and easy-to-use Postgres-backed distributed job queue for Elixir. It was inspired by the brilliant [Que](https://github.com/chanks/que) library for Ruby and uses advisory locks for speed.

You might consider using Rihanna if:

- You need durable asynchronous jobs that are guaranteed to run even if the BEAM is restarted
- You want a [beautiful web GUI](https://github.com/samphilipd/rihanna_ui) that allows you to inspect, delete and retry failed jobs
- You want a simple queue that uses your existing Postges database and doesn't require any additional services or dependencies
- You need to process less than about 1000 jobs per second (if you need more throughout than this you should probably skip Redis and consider a "real" messaging system like Kafka or ActiveMQ)
- You want to pass in arbitrary Elixir/Erlang terms that may not be JSON-serializable such as tuples or structs into your async function calls


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

Rihanna stores jobs in a table in your database. The default table name is "rihanna_jobs".

#### Using Ecto

Run `mix ecto.gen.migration create_rihanna_jobs` and make your migration look like this:

```elixir
defmodule MyApp.CreateRihannaJobs do
  use Rihanna.Migration
end
```

Now you can run `mix ecto.migrate`.

#### Without Ecto

Ecto is not required to run Rihanna. If you want to create the table yourself, without Ecto, take a look at the docs for [Rihanna.Migration](insert_link_to_docs_here).

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

Q. What guarantees does Rihanna provide?

Rihanna guarantees at-least-once execution of jobs regardless of node failures, netsplits or even database restarts.

Rihanna strives to never execute a job more than once, however, this may be unavoidable in certain failure scenarios such as

- a node losing its connection to the database
- a node dying while executing a job

For this reason jobs should be made idempotent where possible.

Q. How many jobs per second can Rihanna process?

Performance is at least as good as [Que](https://github.com/chanks/que).

I have seen it do around 1.5k jobs per second on a mid-2016 Macbook Pro. Significantly higher throughputs are possible with a beefier database server.

More detailed benchmarks to come. For now see: [https://github.com/chanks/queue-shootout](https://github.com/chanks/queue-shootout).

Q. Why Rihanna?

A. Because she knows how to [work, work, work, work, work](https://youtu.be/HL1UzIK-flA?t=18s).

