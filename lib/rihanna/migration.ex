defmodule Rihanna.Migration do
  defmacro change(table_name \\ "rihanna_jobs") do
    quote do
      create table(unquote(table_name)) do
        add :mfa, :bytea, null: false
        add :enqueued_at, :utc_datetime, null: false
        add :updated_at, :utc_datetime, null: false
        add :state, :string, null: false, default: "ready_to_run"
        add :expires_at, :utc_datetime
        add :failed_at, :utc_datetime
        add :fail_reason, :text
      end

      create constraint(
        unquote(table_name),
        "state_value_is_valid",
        check: ~s|state IN ('failed', 'ready_to_run', 'in_progress')|,
        comment: ~s(Valid states are 'ready_to_run', 'in_progress' or 'failed')
      )

      create constraint(
        unquote(table_name),
        "failures_must_set_failed_at_and_fail_reason",
        check: ~s|(state = 'failed' AND failed_at IS NOT NULL AND fail_reason IS NOT NULL) OR state != 'failed'|,
        comment: ~s(When marking a job as 'failed', you must set failed_at and fail_reason)
      )

      create constraint(
        unquote(table_name),
        "only_in_progress_must_set_expires_at",
        check: ~s|expires_at IS NULL OR (state = 'in_progress' AND expires_at IS NOT NULL)|,
        comment: ~s(If job state is 'in_progress', expires_at must be set. Otherwise it must be NULL.)
      )


      execute """
        CREATE FUNCTION fn_notify_insert_job()
          RETURNS trigger AS $$
        DECLARE
        BEGIN
          PERFORM pg_notify(
            'insert_job',
            json_build_object(
              'table', TG_TABLE_NAME,
              'type', TG_OP,
              'id', NEW.id
            )::text
          );
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql
      """, "DROP FUNCTION IF EXISTS fn_notify_insert_job()"

      execute """
        CREATE TRIGGER trg_notify_insert_job
        AFTER INSERT
        ON #{unquote(table_name)}
        FOR EACH ROW
        EXECUTE PROCEDURE fn_notify_insert_job();
      """, "DROP TRIGGER IF EXISTS trg_notify_insert_job ON jobs"
    end
  end
end
