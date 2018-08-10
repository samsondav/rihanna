{:ok, _} = Application.ensure_all_started(:postgrex)

{:ok, _} =
  Postgrex.start_link(
    Application.fetch_env!(:rihanna, :postgrex)
    |> Keyword.put(:name, Rihanna.Job.Postgrex)
  )

ExUnit.start()
