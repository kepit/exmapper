defmodule Exmapper do
  require Logger

  def connect(params) do
    user = params[:username]
    password = params[:password]
    database = params[:database]
    size = if is_nil(params[:pool_size]), do: 1, else: params[:pool_size]
    encoding = if is_nil(params[:encoding]), do: :utf8, else: params[:encoding]
    pool = if is_nil(params[:repo]), do: :default, else: params[:repo] 
    if is_binary(user), do: user = String.to_char_list(user)
    if is_binary(password), do: password = String.to_char_list(password)
    if is_binary(database), do: database = String.to_char_list(database)
    :application.start(:crypto)
    :application.start(:emysql)
    :emysql.add_pool(pool, [{:size,size}, {:user,user}, {:password,password}, {:database,database}, {:encoding,encoding}])
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
    ret = :emysql.execute(pool, query, args)
    after_time = :os.timestamp()
    diff = :timer.now_diff(after_time, before_time)
    Logger.debug fn -> 
      "[#{diff/1000}ms] #{Enum.reduce(args, query, fn(x, acc) -> String.replace(acc, "?", inspect(x), global: false) end)}"
    end
    normalize_result(:emysql, ret)
  end

  
  def normalize_result(:emysql, {:result_packet,_,_,_,_} = ret) do
    {:ok, :emysql.as_proplist(ret)}
  end
  
  def normalize_result(:emysql, {:ok_packet, _seq_num, affected_rows, insert_id, status, warning_count, msg}) do
    {:ok, [insert_id: insert_id, affected_rows: affected_rows, status: status, msg: msg, warning_count: warning_count]}
  end

  def normalize_result(:emysql, {:error_packet, _seq_num, code, msg}) do
    Logger.error "Code: #{code} #{msg}"
    {:error, [code: code, msg: msg]}
  end

  def to_proplist(result) do
    :emysql.as_proplist(result)
  end

  defp where_transform("in", value), do: ["IN","(" <> Enum.join(Enum.map(value, fn(_v) -> "?" end),",") <> ")", value]
  defp where_transform("gt", value), do: [">","?", value]
  defp where_transform("gte", value), do: [">=","?", value]
  defp where_transform("lt", value), do: ["<","?", value]
  defp where_transform("lte", value), do: ["<=","?", value]
  defp where_transform("like", value), do: ["LIKE","?", value]
  defp where_transform(_, value), do: ["=","?", value]

  def where(keyword \\ []) do
    if Enum.count(keyword) > 0 do
      {ret, values} = Enum.map_reduce keyword, [], fn({key,value}, acc) ->
                 key = Atom.to_string(key)
                 oper = List.last(String.split(key,"."))
                 key = String.replace(key, ".#{oper}","")
                 [mark, qm , value] = where_transform(oper, value)
                 { "#{key} #{mark} #{qm}", acc ++ [value]}
      end
      {"WHERE " <> (ret |> Enum.join(" AND ")), values}
    else
      {"", []}
    end
  end

  def limit(args \\ []) do
    if Keyword.has_key?(args,:limit) do
      if is_integer(args[:limit]) do 
      {"LIMIT ?",[args[:limit]]}
      else 
      {"",[]} 
      end
    else
      {"", []}
    end
  end

  def order_by(args \\ []) do
    if Keyword.has_key?(args,:order_by) do
      if args[:order_by] != "" && is_binary(args[:order_by]) do
        {"ORDER BY ?",[args[:order_by]]}
      else
        {"", []}
      end
    else
      {"", []}
    end
  end
  
  
  def count(table, args \\ [], pool \\ :default), do: select("COUNT(*)",table, args) |> query(pool) |> elem(1)
  def all(table, args \\ [], pool \\ :default), do: select("*",table,args,"id ASC") |> query(pool) |> elem(1)
  def first(table, args \\ [], pool \\ :defaut), do: select("*", table,Keyword.merge([limit: 1],args),"id ASC") |> query(pool) |> elem(1)
  def last(table, args \\ [], pool \\ :defaut), do: select("*", table,Keyword.merge([limit: 1],args),"id DESC") |> query(pool) |> elem(1)
  def get(table, id, pool \\ :default), do: select("*", table, [id: id]) |> query(pool) |> elem(1)


  def select(what, table, args, default_order_by \\ "") do
    if what == "", do: what = "*"

    {order_by_sql, order_by_args} = order_by(args)
    args = Keyword.delete(args,:order_by)
    if (order_by_sql == "" and default_order_by != "") do
      {order_by_sql, order_by_args} = order_by(order_by: default_order_by)
    end


    {limit_sql, limit_args} = limit(args)
    args = Keyword.delete(args,:limit)

    {where_sql, where_args} = where(args)
    
    sql = "SELECT #{what} FROM #{table} #{where_sql} #{order_by_sql} #{limit_sql}"
    sql_args = List.flatten(where_args ++ order_by_args ++ limit_args)
    {sql, sql_args}
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
