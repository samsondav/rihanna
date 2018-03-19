defmodule Sombrero.Repo.Migrations.AddInsertedJobTrigger do
  use Ecto.Migration

  def up do
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
    """

    execute """
    CREATE TRIGGER trg_notify_insert_job
    AFTER INSERT
    ON jobs
    FOR EACH ROW
    EXECUTE PROCEDURE fn_notify_insert_job();
    """
  end

  def down do
    execute("DROP TRIGGER IF EXISTS trg_notify_insert_job ON jobs")
    execute("DROP FUNCTION IF EXISTS fn_notify_insert_job()")
  end
end
