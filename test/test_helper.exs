{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Application.ensure_all_started(:ecto)

postgrex_config = Application.fetch_env!(:rihanna, :postgrex)

{:ok, _} =
  postgrex_config
  |> Keyword.put(:name, Rihanna.Job.Postgrex)
  |> Postgrex.start_link()

ExUnit.start(capture_log: true)
