defmodule Rihanna do
  @moduledoc """
  The primary client interface for Rihanna.

  There are two ways to dispatch jobs with Rihanna:

  1. Using mod-fun-args which is a bit like RPC
  2. Using a module that implements `Rihanna.Job` and passing in one argument

  See the documentation for `enqueue/1` and `enqueue/2` for more details.

  ## Supervisor

  You must have started `Rihanna.Supervisor` otherwise you will see an error trying
  to enqueue or retry jobs.

  ## Database Connections

  Rihanna requires 1 + N database connections per node, where 1 connection is used
  for the external API of enqueuing/retrying jobs and N is the number of
  dispatchers. The default configuration is to run one dispatcher per node, so
  this will use 2 database connections.

  ## Notes on queueing

  Rihanna uses a FIFO job queue, so jobs will be processed roughly in the order
  that they are enqueued. However, because Rihanna is a concurrent job queue,
  it may have multiple workers processing jobs at the same time so there is no
  guarantee of any ordering in practice.

  ## Scheduling

  You can schedule jobs for deferred execution using `schedule/2` and
  `schedule/3`. Jobs scheduled for later execution will run shortly after the
  due at date, but there is no guarantee on exactly when they will run.

  """

  @enqueue_help_message """
  Rihanna.Enqueue requires either one argument in the form {mod, fun, args} or
  two arguments of a module implementing Rihanna.Job and its arg.

  For example, to run IO.puts("Hello"):

  > Rihanna.enqueue({IO, :puts, ["Hello"]})

  Or, if you have a job called MyJob that implements the Rihanna.Job behaviour:

  > Rihanna.enqueue(MyJob, arg)
  """

  @doc """
  Enqueues a job specified as a simple mod-fun-args tuple.

  ## Example

      > Rihanna.enqueue({IO, :puts, ["Umbrella-ella-ella"]})
  """
  @spec enqueue({module, atom, list()}) :: {:ok, Rihanna.Job.t()}
  def enqueue(term = {mod, fun, args}) when is_atom(mod) and is_atom(fun) and is_list(args) do
    Rihanna.Job.enqueue(term)
  end

  def enqueue(_) do
    raise ArgumentError, @enqueue_help_message
  end

  @doc """
  Enqueues a job specified as a module and one argument.

  It is expected that the module implements the `Rihanna.Job` behaviour and
  defines a function `c:Rihanna.Job.perform/1`.

  The argument may be anything.

  See `Rihanna.Job` for more on how to implement your own jobs.

  You can enqueue a job like so:

  ```
  # Enqueue job for later execution and return immediately
  Rihanna.enqueue(MyApp.MyJob, [arg1, arg2])
  ```
  """
  @spec enqueue(module, any) :: {:ok, Rihanna.Job.t()}
  def enqueue(mod, arg) when is_atom(mod) do
    Rihanna.Job.enqueue({mod, arg})
  end

  def enqueue(_, _) do
    raise ArgumentError, @enqueue_help_message
  end

  @type schedule_option ::
          {:at, DateTime.t()}
          | {:in, pos_integer}
          | {:due_at, DateTime.t()}
          | {:priority, pos_integer()}
  @type schedule_options :: [schedule_option]

  @doc """
  Schedule a job specified as a simple mod-fun-args tuple to run later.

  ## Example

  Schedule at a `DateTime`:

      due_at = ~N[2018-07-01 12:00:00] |> DateTime.from_naive!("Etc/UTC")
      Rihanna.schedule({IO, :puts, ["Umbrella-ella-ella"]}, at: due_at)

  Schedule in 5 minutes:

      Rihanna.schedule({IO, :puts, ["Umbrella-ella-ella"]}, in: :timer.minutes(5))

  """
  @spec schedule({module, atom, list()}, schedule_options) :: {:ok, Rihanna.Job.t()}
  def schedule(term = {mod, fun, args}, schedule_options)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    Rihanna.Job.enqueue(term, due_at: due_at(schedule_options))
  end

  @doc """
  Schedule a job specified as a module and one argument to run later.

  It is expected that the module implements the `Rihanna.Job` behaviour and
  defines a function `c:Rihanna.Job.perform/1`.

  The argument may be anything.

  See `Rihanna.Job` for more on how to implement your own jobs.

  ## Example

  Schedule at a `DateTime`:

      due_at = DateTime.from_naive!(~N[2018-07-01 12:00:00], "Etc/UTC")
      Rihanna.schedule(MyApp.MyJob, [arg1, arg2], at: due_at)

  Schedule in 5 minutes:

      Rihanna.schedule(MyApp.MyJob, [arg1, arg2], in: :timer.minutes(5))

  """
  @spec schedule(module, any, schedule_options) :: {:ok, Rihanna.Job.t()}
  def schedule(mod, arg, schedule_options) when is_atom(mod) do
    Rihanna.Job.enqueue({mod, arg}, due_at: due_at(schedule_options))
  end

  @doc """
  Retries a job by ID. ID can be passed as either integer or string.

  Note that this only works if the job has failed - if it has not yet run or is
  currently in progress, this function will do nothing.
  """
  @spec retry(String.t()) :: {:ok, :retried} | {:error, :job_not_found}
  def retry(job_id) when is_binary(job_id) do
    job_id
    |> String.to_integer()
    |> retry()
  end

  @spec retry(integer) :: {:ok, :retried} | {:error, :job_not_found}
  def retry(job_id) when is_integer(job_id) and job_id > 0 do
    Rihanna.Job.retry_failed(job_id)
  end

  @doc """
  Deletes a job by ID. ID can be passed as either integer or string.

  """
  @spec delete(String.t() | integer) :: {:ok, Rihanna.Job.t()} | {:error, :job_not_found}
  def delete(job_id) when is_binary(job_id) do
    job_id
    |> String.to_integer()
    |> delete()
  end

  def delete(job_id) when is_integer(job_id) and job_id > 0 do
    Rihanna.Job.delete(job_id)
  end

  defp due_at(at: %DateTime{} = due_at), do: due_at

  defp due_at(in: due_in) when is_integer(due_in) and due_in > 0 do
    now = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    DateTime.from_unix!(now + due_in, :millisecond)
  end
end
