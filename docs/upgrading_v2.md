# Upgrading to Rihanna v2

Upgrading to Rihanna >= v2.0.0 requires the addition of a required column and a
change in the index used to perform fast job locking. As this column is required
it will break Rihanna prior to v2. However, v2 and up will not work without this
column present.

There are a number of ways to perform this database migration to prevent errors
in production. Here are a few ways that we propose. If job processing is required to
avoid downtime, another approach may be required.

## Option 1: Stop the world downtime

### Preparing

1. Upgrade Rihanna to v2 using `mix`
2. Create a new migration e.g., `mix ecto.gen.migration`
3. Add `use Rihanna.Migration.Upgrade` to your migration

```elixir
defmodule MyApp.UpgradeRihannaJobs do
  use Rihanna.Migration.Upgrade
end
```

### Deploying the changes

1. Stop your application, jobs cannot be enqueued or worked during the migration.
2. Deploy new code, but do not start it running
3. Perform the migration using `mix ecto.migrate`
4. Start your the application again, now running Rihanna v2

## Option 2: Direct SQL upgrade

This options should only be attempted if you feel VERY comfortable with SQL

1. While the existing code is running, add the new column and index (replace `rihanna_jobs`) with your own table:

```
ALTER TABLE rihanna_jobs ADD COLUMN priority integer;
CREATE INDEX CONCURRENTLY rihanna_jobs_priority_enqueued_at_id ON rihanna_jobs (priority ASC, enqueued_at ASC, id ASC);
```

2. Upgrade your code to use Rihanna v2 and release/deploy
3. After the new code is running, set the default value on priority

```
ALTER TABLE rihanna_jobs ALTER COLUMN priority SET DEFAULT 50;
```

4. Backfill default value for any null priority jobs

```
UPDATE rihanna_jobs SET priority = 50 WHERE priority IS NULL;
```

5. Make the priority column NOT NULL

```
ALTER TABLE rihanna_jobs ALTER COLUMN priority SET NOT NULL;
```
