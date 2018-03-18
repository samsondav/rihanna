defmodule Sombrero.ETF do
  @behaviour Ecto.Type

  def type, do: :bytea

  def load(serialized_mfa) when is_binary(serialized_mfa) do
    {:ok, :erlang.binary_to_term(serialized_mfa)}
  end

  def load(nil, _), do: {:ok, nil}
  def load(_, _), do: :error

  def dump(mfa) do
    {:ok, :erlang.term_to_binary(mfa)}
  end

  def cast(mfa = {mod, fun, args}) when is_atom(mod) and is_atom(fun) and is_list(args) do
    {:ok, mfa}
  end
  def cast(_), do: :error
end
