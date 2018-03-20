defmodule Sombrero do
  @moduledoc """
  TODO: Write some documentation for Sombrero.
  """
  def enqueue(mfa = {mod, fun, args}) when is_atom(mod) and is_atom(fun) and is_list(args) do
    job = %Sombrero.Job{
      mfa: mfa,
      state: "ready_to_run"
    }

    Sombrero.Repo.insert(job)
  end

  def enqueue(_) do
    raise ArgumentError, """
    Sombrero.Enqueue requires one argument in the form {mod, fun, args}.

    For example, to run IO.puts("Hello"):

    > Sombrero.enqueue({IO, :puts, ["Hello"]})
    """
  end
end
