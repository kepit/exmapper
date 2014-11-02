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
    Logger.debug(query)
    :emysql.prepare(:q, query)
    :emysql.execute(pool, :q, Enum.map(args,fn(x) ->
                                          cond do
                                            is_boolean(x) ->
                                              if x == true do
                                                1
                                              else
                                                0
                                              end
                                            true ->
                                              x
                                          end
                                        end))
  end

  def to_proplist(result) do
    :emysql.as_proplist(result)
  end

  defp where(keyword \\ []) do
    Enum.join(Enum.map(keyword, fn({key,value}) ->
                         mark = "="
                         key = Atom.to_string(key)
                         case List.last(String.split(key,".")) do
                           "gt" ->
                             mark = ">"
                           "gte" ->
                             mark = ">="
                           "lt" ->
                             mark = "<"
                           "lte" ->
                             mark = "<="
                           "like" -> 
                             mark = "LIKE"
                           "in" ->
                             mark = "IN"
                           _ ->
                             mark = "="
                         end
                         key = String.replace(key,~r/.gte|.gt|.lte|.lt|.like|.in/,"")
                         val = "?"
                         if mark == "IN" do
                           questions = Enum.join(Enum.map(value, fn(v) -> "?" end),",")
                           val = "(#{questions})"
                         end
                         "#{key} #{mark} #{val}" #"?"
                       end)," AND ")
  end

  def all(table, args \\ [], pool \\ :default) do
    where = ""
    limit = ""
    order_by = "id ASC"
    if Keyword.has_key?(args,:limit) do
      if is_integer(args[:limit]), do: limit = "LIMIT #{args[:limit]}"
      args = Keyword.delete(args,:limit)
    end
    if Keyword.has_key?(args,:order_by) do
      if args[:order_by] != "" && is_binary(args[:order_by]), do: order_by = args[:order_by]
      args = Keyword.delete(args,:order_by)
    end
    if Enum.count(args) > 0 do
      where = "WHERE #{where(args)} "
    end
    query("SELECT * FROM #{table} #{where}ORDER BY #{order_by} #{limit}",List.flatten(Keyword.values(args)),pool)
  end

  def count(table, args \\ [], pool \\ :default) do
    where = ""
    if Enum.count(args) > 0 do
      where = "WHERE #{where(args)} "
    end
    query("SELECT COUNT(*) FROM #{table} #{where}",Keyword.values(args),pool)
  end

  def first(table, args \\ [], pool \\ :default) do
    where = ""
    limit = 1
    order_by = "id ASC"
    if Keyword.has_key?(args,:limit) do
      limit = args[:limit]
      args = Keyword.delete(args,:limit)
    end
    if Keyword.has_key?(args,:order_by) do
      if args[:order_by] != "" && is_binary(args[:order_by]), do: order_by = args[:order_by]
      args = Keyword.delete(args,:order_by)
    end
    if Enum.count(args) > 0 do
      where = "WHERE #{where(args)} "
    end
    query("SELECT * FROM #{table} #{where}ORDER BY #{order_by} LIMIT #{limit}",List.flatten(Keyword.values(args)),pool)
  end

  def last(table, args \\ [], pool \\ :defaut) do
    where = ""
    limit = 1
    order_by = "id DESC"
    if Keyword.has_key?(args,:limit) do
      limit = args[:limit]
      args = Keyword.delete(args,:limit)
    end
    if Keyword.has_key?(args,:order_by) do
      if args[:order_by] != "" && is_binary(args[:order_by]), do: order_by = args[:order_by]
      args = Keyword.delete(args,:order_by)
    end
    if Enum.count(args) > 0 do
      where = "WHERE #{where(args)} "
    end
    query("SELECT * FROM #{table} #{where}ORDER BY #{order_by} LIMIT #{limit}",List.flatten(Keyword.values(args)),pool)
  end

  def get(table, id, pool \\ :default) do
    query("SELECT * FROM #{table} WHERE id = ? LIMIT 1",[id],pool)
  end

  def to_keywords(value) do
    if is_list(value) do
      Enum.map(value, fn(x) -> to_keywords(x) end)
    else
      value = Keyword.delete(Map.to_list(value), :__struct__)
      Keyword.delete(Enum.map(value, fn({key,val}) ->
                                if is_map(val) do
                                  {key,to_keywords(val)}
                                else
                                  if is_function(val) do
                                    nil
                                  else
                                    {key,val}
                                  end
                                end
                              end),nil)
    end
  end
  
  def module_to_id(module) do
    String.to_atom((module |> Module.split |> List.last |> Mix.Utils.underscore) <> "_id")
  end
end
