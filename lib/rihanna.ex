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

  ## Notes on queueing

  Rihanna uses a FIFO job queue, so jobs will be processed roughly in the order
  that they are enqueued. However, because Rihanna is a concurrent job queue,
  it may have multiple workers processing jobs at the same time so there is no
  guarantee of any ordering in practice.

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
  @spec enqueue({module, atom, list()}) :: {:ok, Rihanna.Job.t}
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
  # schedule job for later execution and return immediately
  Rihanna.enqueue(MyApp.MyJob, [arg1, arg2])
  ```
  """
  @spec enqueue(module, any) :: {:ok, Rihanna.Job.t}
  def enqueue(mod, arg) when is_atom(mod) do
    Rihanna.Job.enqueue({mod, arg})
  end

  def enqueue(_, _) do
    raise ArgumentError, @enqueue_help_message
  end

  @doc """
  Retries a job by ID. ID can be passed as either integer or string.

  Note that this only works if the job has failed - if it has not yet run or is
  currently in progress, this function will do nothing.
  """
  @spec retry(String.t) :: {:ok, :retried} | {:error, :job_not_found}
  def retry(job_id) when is_binary(job_id) do
    job_id
    |> String.to_integer
    |> retry()
  end

  @spec retry(integer) :: {:ok, :retried} | {:error, :job_not_found}
  def retry(job_id) when is_integer(job_id) and job_id > 0 do
    Rihanna.Job.retry_failed(job_id)
  end
end
