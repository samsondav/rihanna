defmodule Rihanna do
  @moduledoc """
  TODO: Write some documentation for Rihanna.
  """
  def enqueue(mfa = {mod, fun, args}) when is_atom(mod) and is_atom(fun) and is_list(args) do
    Rihanna.Job.enqueue(mfa)
  end

  def enqueue(_) do
    raise ArgumentError, """
    Rihanna.Enqueue requires one argument in the form {mod, fun, args}.

    For example, to run IO.puts("Hello"):

    > Rihanna.enqueue({IO, :puts, ["Hello"]})
    """
  end
end
