defmodule Exmapper.Adapter do
  require Logger

  def adapter do
    Exmapper.Adapters.Mariaex
  end

  def connect(params) do
    adapter().connect(params)
  end

  def query({query, args}) do
    query({query,args},:default)
  end

  def query({query, args}, pool) do
    if is_nil(pool), do: pool = :default
    query(query, args, pool)
  end

  def query(query, args, pool \\ :default) do
    before_time = :os.timestamp()
    ret = adapter().query(pool, query, args)
    after_time = :os.timestamp()
    diff = :timer.now_diff(after_time, before_time)
    Logger.debug fn -> 
      "[#{diff/1000}ms] #{Enum.reduce(args, query, fn(x, acc) -> String.replace(acc, "?", inspect(x), global: false) end)}"
    end
    adapter().normalize_result(ret)
  end


end
