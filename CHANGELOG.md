# Changelog

## [Unreleased]

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
