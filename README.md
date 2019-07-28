# Rihanna

[![Package Version](https://img.shields.io/hexpm/v/rihanna.svg)](https://hex.pm/packages/rihanna)
[![Documentation](https://img.shields.io/badge/docs-latest-blue.svg)](https://hexdocs.pm/rihanna/)

Rihanna is a fast, reliable and easy-to-use Postgres-backed distributed job queue for Elixir. It was inspired by the brilliant [Que](https://github.com/chanks/que) library for Ruby and uses advisory locks for speed.

You might consider using Rihanna if:

- You need durable asynchronous jobs that are guaranteed to run even if the BEAM is restarted
- You want ACID guarantees around your jobs so you can be 100% sure they will never be lost
- You want a [beautiful web GUI](https://github.com/samphilipd/rihanna_ui) that allows you to inspect, delete and retry failed jobs
- You want a simple queue that uses your existing Postgres database and doesn't require any additional services or dependencies
- You need to process up to 10,000 jobs per second (if you need more throughput than this you should probably consider a "real" messaging system like Kafka or ActiveMQ)
- You want to pass arbitrary Elixir/Erlang terms that may not be JSON-serializable such as tuples or structs as arguments

## Contents

- [Requirements](#requirements)
- [Usage](#usage)
- [Installation](#installation)
  - [With Ecto](#with-ecto)
  - [Without Ecto](#without-ecto)
- [Configuration](#configuration)
- [Upgrading](#upgrading)
- [FAQs](#faqs)

## Requirements

Rihanna requires Elixir >= 1.5 (OTP >= 18.0) and Postgres >= 9.5

## Usage

There are two ways to use Rihanna. The simplest way is to pass a mod-fun-args tuple like so:

```elixir
# Enqueue job for later execution and return immediately
Rihanna.enqueue({MyModule, :my_fun, [arg1, arg2]})
```

The second way is to implement the `Rihanna.Job` behaviour and define the `perform/1` function. Implementing this behaviour allows you to define retry strategies, show custom error messages on failure etc. See [the docs](https://hexdocs.pm/rihanna/Rihanna.Job.html) for more details.

```elixir
defmodule MyApp.MyJob do
  @behaviour Rihanna.Job

  # NOTE: `perform/1` is a required callback. It takes exactly one argument. To
  # pass multiple arguments, wrap them in a list and destructure in the
  # function head as in this example
  def perform([arg1, arg2]) do
    success? = do_some_work(arg1, arg2)

    if success? do
      # job completed successfully
      :ok
    else
      # job execution failed
      {:error, :failed}
    end
  end
end
```

Now you can enqueue your jobs like so:

```elixir
# Enqueue job for later execution and return immediately
Rihanna.enqueue(MyApp.MyJob, [arg1, arg2])
```

### Job scheduling

You can schedule jobs for deferred execution using `schedule/2` and `schedule/3`.

Schedule at a `DateTime`:

```elixir
Rihanna.schedule(
  {IO, :puts, ["Hello"]},
  at: DateTime.from_naive!(~N[2018-07-01 12:00:00], "Etc/UTC")
)
```

Schedule in one hour:

```elixir
Rihanna.schedule({IO, :puts, ["Hello"]}, in: :timer.hours(1))
```

Jobs scheduled for later execution will run _after_ their scheduled date, but there is no guarantee they will run at exactly their due date as this will depend on your configured poll interval and what other jobs are being processed.

## Installation

### With Ecto

#### Step 1 - add the dependency

Add `rihanna` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rihanna, "~> 1.3"},
  ]
end
```

Install with `mix deps.get`.

#### Step 2 - migrate the database

Add a migration to create your jobs table.

Rihanna stores jobs in a table in your database. The default table name is "rihanna_jobs".

Run `mix ecto.gen.migration create_rihanna_jobs` and make your migration look like this:

```elixir
defmodule MyApp.CreateRihannaJobs do
  use Rihanna.Migration
end
```

Now you can run `mix ecto.migrate`.

#### Step 3 - configure Rihanna to use your Ecto Repo

When using Ecto Rihanna can reuse your Ecto Repo to enqueue and schedule jobs, rather than creating a new database connection for these actions. This will also make Rihanna use the Ecto sandbox in test so you can run tests that enqueue jobs asynchronously.

Note Rihanna will still create a dedicated database connection outside of the Repo for the dispatcher to poll for new jobs.

```elixir
# config/config.exs
config :rihanna,
  producer_postgres_connection: {Ecto, MyApp.Repo} # Use the name of your Repo here
```

#### Step 4 - boot the supervisor

Add `Rihanna.Supervisor` to your supervision tree

`Rihanna.Supervisor` starts a job dispatcher and by adding it to your supervision tree it will automatically start running jobs when your app boots.

Rihanna requires a database configuration to be passed in under the `postgrex` key. This is passed through directly to Postgrex.

If you are already using Ecto you can avoid duplicating your DB config by pulling this out of your existing Repo using `My.Repo.config()`.

```elixir
# Elixir 1.6+
# NOTE: In Phoenix you would find this inside `lib/my_app/application.ex`
children = [
  {Rihanna.Supervisor, [postgrex: My.Repo.config()]}
]
```

```elixir
# Elixir 1.5
import Supervisor.Spec, warn: false

children = [
  supervisor(Rihanna.Supervisor, [[postgrex: My.Repo.config()]])
]
```


### Without Ecto

#### Step 1 - add the dependency

Add `rihanna` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rihanna, ">= 0.0.0"}
  ]
end
```

Install with `mix deps.get`.

**Note:** `Postgrex` requires some JSON library. `Jason` is the default they suggest,
but if you are using a different library, please configure `Postgrex` to use it.
[Read more details in the Postgrex docs.](https://github.com/elixir-ecto/postgrex#json-support)

#### Step 2 - migrate the database

Make sure you dependencies are compiled with `mix deps.compile`.

Run `mix rihanna.migrate` to create the table that Rihanna uses to store jobs ("rihanna_jobs" by default) and others necessary objects.

#### Step 3 - boot the supervisor

Add `Rihanna.Supervisor` to your supervision tree

`Rihanna.Supervisor` starts a job dispatcher and by adding it to your supervision tree it will automatically start running jobs when your app boots.

Rihanna requires a database configuration to be passed in under the `postgrex` key. This is passed through directly to Postgrex.

If you are already using Ecto you can avoid duplicating your DB config by pulling this out of your existing Repo using `My.Repo.config()`.

```elixir
# Elixir 1.6+
# NOTE: In Phoenix you would find this inside `lib/my_app/application.ex`
children = [
  {Rihanna.Supervisor, [name: Rihanna.Supervisor, postgrex: My.Repo.config()]}
]
```

```elixir
# Elixir 1.5
import Supervisor.Spec, warn: false

children = [
  supervisor(Rihanna.Supervisor, [[name: Rihanna.Supervisor, postgrex: My.Repo.config()]])
]
```

## Configuration

Rihanna should work out of the box without any configuration. However, should you
wish to tweak it, take a look at the documentation for [Rihanna.Config](https://hexdocs.pm/rihanna/Rihanna.Config.html).

## Upgrading

Please refer to the [Changelog](CHANGELOG.md) for details on when a database upgrade is required and how to migrate the Rihanna jobs table.

## FAQs

**Q: What does the supervision tree look like/how does Rihanna work?**

![Architecture/Supervision tree](docs/architecture.png?raw=true "Rihanna supervision tree")

**Q: How many jobs can be processed concurrently?**

By default Rihanna processes a maximum of 50 jobs per dispatcher. This number is configurable, see [the docs](https://hexdocs.pm/rihanna/0.5.2/Rihanna.Config.html#dispatcher_max_concurrency/0).

**Q. What guarantees does Rihanna provide?**

Rihanna guarantees at-least-once execution of jobs regardless of node failures, netsplits or even database restarts.

Rihanna strives to never execute a job more than once, however, this may be unavoidable in certain failure scenarios such as

- a node losing its connection to the database
- a node dying during execution of a job

For this reason jobs should be made idempotent where possible.

**Q: Are there any limits on job duration?**

No. Rihanna jobs run for as long as they need to.

One thing to be aware of is that if you restart your application (e.g. because you deployed) then all running jobs on that node will be exited. For this reason it is probably sensible not to make your jobs take an extremely long time.

**Q: How many database connections does Rihanna hold open?**

Rihanna requires 1 + N database connections per node, where 1 connection is used
for the external API of enqueuing/retrying jobs and N is the number of
dispatchers.

In the default configuration of one dispatcher per node, Rihanna will use 2
database connections per node.

It is possible to reuse an existing Postgres connection (such as an Ecto Repo) for enqueuing etc, bringing the number of connections down to N where N is the number of dispatchers. See [Rihanna.Config](https://hexdocs.pm/rihanna/Rihanna.Config.html) for more information.

**Q. How fast is Rihanna?**

Performance should be at least as good as [Que](https://github.com/chanks/que).

I have seen it do around 1.5k jobs per second on a mid-2016 Macbook Pro. Significantly higher throughputs are possible with a beefier database server.

More detailed benchmarks to come. For now see: [https://github.com/chanks/queue-shootout](https://github.com/chanks/queue-shootout).

**Q. Does it support multiple queues?**

Not yet, but it will.

**Q. Does it support cron tasks/recurring jobs?**

Yes! To implement a recurring job have the job reschedule itself after completion and Postgres' ACID guarantees will ensure that it continues running. You will need to enqueue the job manually the first time from the console.

**Q. Are there risks of arbitrary code execution with the MFA variant?**

Short answer: No.

Long answer:

In order to do anything the attacker first needs to have obtained write access to your production database. In most companies, internal and customer data is far more important than whatever code is executing so you're already effectively hosed at this point.

By default you can call Rihanna with any mod-fun-args tuple. This does give a potential attacker a few more options than if they were restricted to simply calling the `perform/1` function on an existing module with different arguments.

If you really want to turn this behaviour off, you can set the `behaviour_only` config option to `true`.

**Q. Why Rihanna?**

Because she knows how to [work, work, work, work, work](https://youtu.be/HL1UzIK-flA?t=18s).
