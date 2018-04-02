defmodule Rihanna do
  @moduledoc """
  TODO: Write some documentation for Rihanna.
  """

  @enqueue_help_message """
    Rihanna.Enqueue requires either one argument in the form {mod, fun, args} or
    two arguments of a module implementing Rihanna.Job and its arg.

    For example, to run IO.puts("Hello"):

    > Rihanna.enqueue({IO, :puts, ["Hello"]})

    Or, if you have a job called MyJob that implements the Rihanna.Job behaviour:

    > Rihanna.enqueue(MyJob, arg)
    """

  def enqueue(term = {mod, fun, args}) when is_atom(mod) and is_atom(fun) and is_list(args) do
    Rihanna.Job.enqueue(term)
  end

  def enqueue(_) do
    raise ArgumentError, @enqueue_help_message
  end

  def enqueue(mod, arg) when is_atom(mod) do
    Rihanna.Job.enqueue({mod, arg})
  end

  def enqueue(_, _) do
    raise ArgumentError, @enqueue_help_message
  end

  def retry(job_id) when is_binary(job_id) do
    job_id
    |> String.to_integer
    |> retry()
  end

  def retry(job_id) when is_integer(job_id) and job_id > 0 do
    Rihanna.Job.retry_failed(job_id)
  end
end
