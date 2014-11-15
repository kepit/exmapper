defmodule Exmapper do
  require Logger

  def adapter do
    Exmapper.Mysql
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

  def to_keywords(value) do
    if value == nil do
      nil
    else
      if is_list(value) do
        Enum.map(value, fn(x) -> to_keywords(x) end)
      else
        value = Keyword.delete(Map.to_list(value), :__struct__)
        Enum.reject(Enum.map(value, fn({key,val}) ->
                               if is_map(val) do
                                 {key,to_keywords(val)}
                               else
                                 if is_function(val) do
                                   nil
                                 else
                                   {key,val}
                                 end
                               end
                             end),fn(x) -> is_nil(x) end)
      end
    end
  end
  
  def module_to_id(module) do
    String.to_atom((module |> Module.split |> List.last |> Mix.Utils.underscore) <> "_id")
  end

  def is_virtual_type(type), do: (Enum.find([:virtual, :belongs_to, :has_many, :setter],fn(x) -> x == type end) != nil) 

end
