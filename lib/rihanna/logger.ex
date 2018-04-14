defmodule Rihanna.Logger do
  require Logger

  def log(level, chardata_or_fun) do
    if Rihanna.Config.debug? do
      Logger.log(level, chardata_or_fun)
    end
  end
end
