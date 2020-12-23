# Changelog

## v2.3.0

- Add job_module to telemetry events - @tpitale

## v2.2.2

- Fix for db checks with multi-schema databases - @rubysolo

## v2.2.0

- DB Upgrade required: Recreate index to add NULLS FIRST on the due_at column on
  jobs table to fix performance of the locking query - @tpitale

## v2.1.1

- Allow users to pass a different repo as parameter

## v2.1.0

- Added `Rihanna.deleted_by/1`

## v2.0.0

- Breaking change: must add `priority` column, which requires downtime. Please
  see [Upgrading v2](docs/upgrading_v2.md) for more detailed instructions.

## 1.3.5

- Drop `pool_size` from Postgrex config in addition to `pool`.

## 1.3.4

- Drop `pool` from Postgrex config as Rihanna requires a single dedicated
  connection.

## v1.3.3

- Relaxed restriction on Postgrex options in supervisor, enabling clients to
  use any Postgrex configuration they want.

## v1.3.1

- Fix incorrect index name being used with custom table name.

## v1.3.0

- The startup delay for the job dispatcher is now configurable.

## v1.2.2

- Rescue after_error callback errors to stop a potential infinite retry loop
  for a job.

## v1.2.1

- Schedule and enqueue functions now raise errors with greater detail when
  given incorrect arguments.
- Fix bug when creating index using a custom table name

## v1.2.0

- Add support for enqueuing job via a user supplied Postgres connection. This
  can be either a Postgrex process or an Ecto Repo.

## v1.1.4

- Add `Rihanna.delete`
- Fix specs in migrations

## v1.1.3

- Fix callback spec for `after_error`
- Fix flaky tests

## v1.1.2

- Fix bug preventing rollback of upgrade migration

## v1.1.1

- Remove `CONCURRENTLY` from migration since it doesn't play well with Ecto.

## v1.1.0

- Add missing index that massively improves performance at high loads

## v1.0.1

- Fix a SQL syntax error in migration rollback.

## v1.0.0

### Added

- Added an optional callback per job which defines what to do when that job errors.

  ```elixir
  def after_error(failure_reason, args) do
    notify_someone(__MODULE__, failure_reason, args)
  end
  ```

## v0.7.0

### Added

- Schedule jobs to run at a `DateTime` or in a number of milliseconds.

  ```elixir
  Rihanna.schedule(
    {IO, :puts, ["Hello"]},
    at: DateTime.from_naive!(~N[2018-07-01 12:00:00], "Etc/UTC")
  )

  Rihanna.schedule({IO, :puts, ["Hello"]}, in: :timer.hours(1))
  ```

### Upgrading

This release requires a database upgrade. The easiest way to upgrade the database is with Ecto. Run `mix ecto.gen.migration upgrade_rihanna_jobs` and make your migration look like this:

```elixir
defmodule MyApp.UpgradeRihannaJobs do
  use Rihanna.Migration.Upgrade
end
```

Now you can run `mix ecto.migrate`.
