# TODO: Use the host application's Repo instaed
defmodule Sombrero.Repo do
  use Ecto.Repo, otp_app: :sombrero, adapter: Ecto.Adapters.Postgres
end
