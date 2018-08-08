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
