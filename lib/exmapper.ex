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

  def query(query, args \\ [], pool \\ :default) do
    before_time = :os.timestamp()
    :emysql.prepare(:q, query)
    ret = :emysql.execute(pool, :q, Enum.map(args,fn(x) ->
                                         Exmapper.Field.Transform.encode(x)
                                        end))
    after_time = :os.timestamp()
    diff = :timer.now_diff(after_time, before_time)
    Logger.debug fn -> 
      "[#{diff/1000}ms] #{query}"
    end
    ret
  end

  def to_proplist(result) do
    :emysql.as_proplist(result)
  end

  defp where_transform("in", value), do: ["IN","(" <> Enum.join(Enum.map(value, fn(v) -> "?" end),",") <> ")", value]
  defp where_transform("gt", value), do: [">","?", value]
  defp where_transform("gte", value), do: [">=","?", value]
  defp where_transform("lt", value), do: ["<","?", value]
  defp where_transform("lte", value), do: ["<=","?", value]
  defp where_transform("like", value), do: ["LIKE","?", value]
  defp where_transform(_, value), do: ["=","?", value]

  defp where(keyword \\ []) do
    if Enum.count(keyword) > 0 do
      ret = Enum.map(keyword, fn({key,value}) ->
                 mark = "="
                 key = Atom.to_string(key)
                 oper = List.last(String.split(key,"."))
                 key = String.replace(key, ".#{oper}","") # Fixme: regexp end
                 [mark, qm, value] = where_transform(oper, value)
                 "#{key} #{mark} #{qm}"
               end) |> Enum.join(" AND ")
      "WHERE #{ret}"
    else
      ""
    end
  end

  def count(table, args \\ [], pool \\ :default), do: select("COUNT(*)",table, args, pool)
  def all(table, args \\ [], pool \\ :default), do: select("*",table,args,pool,"id ASC")
  def first(table, args \\ [], pool \\ :defaut), do: select("*", table,Keyword.merge([limit: 1],args),pool,"id ASC")
  def last(table, args \\ [], pool \\ :defaut), do: select("*", table,Keyword.merge([limit: 1],args),pool,"id DESC")
  def get(table, id, pool \\ :default), do: select("*", table, [id: id], pool)


  defp select(what, table, args, pool, order_by \\ "") do
    limit = ""

    if what == "", do: what = "*"

    if Keyword.has_key?(args,:limit) do
      if is_integer(args[:limit]), do: limit = "LIMIT #{args[:limit]}"
      args = Keyword.delete(args,:limit)
    end

    if order_by != "", do: order_by = "ORDER BY " <> order_by

    if Keyword.has_key?(args,:order_by) do
      if args[:order_by] != "" && is_binary(args[:order_by]), do: order_by = "ORDER BY " <> args[:order_by]
      args = Keyword.delete(args,:order_by)
    end

    query("SELECT #{what} FROM #{table} #{where(args)} #{order_by} #{limit}",List.flatten(Keyword.values(args)),pool)
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
end
