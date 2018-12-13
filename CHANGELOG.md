# Changelog

## Unreleased

- Schedule and enqueue functions now raise errors with greater detail when
  given incorrect arguments.

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
