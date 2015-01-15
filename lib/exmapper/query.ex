defmodule Exmapper.Query do
  require Logger
  
  def build_query(:create, table_name, args, {where_sql, where_args}) do
    args = Keyword.delete(args,:id)
    keys = Keyword.keys(args)
    qmark = Enum.join(List.duplicate(["?"],Enum.count(Keyword.values(args))),",")
    {"INSERT INTO #{table_name} (#{Enum.join(keys,",")}) VALUES (#{qmark})", List.flatten(Keyword.values(args))}
  end

  def build_query(:update, table_name, args, {where_sql, where_args}) do
    set = Enum.join(Enum.map(Keyword.delete(args,:id),fn({key,val}) -> "#{key} = ?" end),", ")
    {"UPDATE #{table_name} SET #{set} #{where_sql}", List.flatten(Keyword.values(Keyword.delete(args,:id)))++where_args}
  end
  
  def build_query(:delete, table_name, {where_sql, where_args}) do
    {"DELETE FROM #{table_name} #{where_sql}", where_args}
  end
  
  def build_query(:select, what, table, args, default_order_by \\ "") do
    select(what, table, args, default_order_by)
  end


  defp where_transform(type, value) when type in ["in"] and is_map(value) do 
    {select_sql, select_args} = select(value.select, value.from, value.where)
    [type,"(" <> select_sql <> ")", select_args]
  end
  defp where_transform(type, value) when type in ["in"] and is_list(value) do 
    [type,"(" <> Enum.join(Enum.map(value, fn(_v) -> "?" end),",") <> ")", value]
  end
  
  defp where_transform(type, value) when type in ["<","<=",">",">=","!=","<>"] do
    [type, "?", value]
  end

  defp where_transform("gt", value), do: [">","?", value]
  defp where_transform("gte", value), do: [">=","?", value]
  defp where_transform("lt", value), do: ["<","?", value]
  defp where_transform("lte", value), do: ["<=","?", value]
  defp where_transform("like", value), do: ["LIKE","?", value]
  defp where_transform(_, value), do: ["=","?", value]
  
  defp build_where([], "AND"), do: {"", []}
  defp build_where([], "OR"), do: {"", []}
  defp build_where(args, joiner) do
    {ret, values} = Enum.map_reduce args, [], fn({key,value}, acc) ->
      case key do
        :and -> 
          {sql_str, vals} = build_where(value, "AND")
          {sql_str, acc ++ vals}
        :or -> 
          {sql_str, vals} = build_where(value, "OR")
          {sql_str, acc ++ vals}
        _ ->
          key = Atom.to_string(key)
          oper = List.last(String.split(key,"."))
          key = String.replace(key, ".#{oper}","")
          [mark, qm , value] = where_transform(oper, value)
          { "#{key} #{mark} #{qm}", acc ++ [value]}
      end
    end
    {"(" <> (ret |> Enum.join(" #{joiner} ")) <> ")", values}
  end

  def where([]), do: {"",[]}
  def where(args) do
    {where_sql, where_args} = build_where(args, "AND")
    {"WHERE " <> where_sql, where_args}
  end

  def select(what, table, args, default_order_by \\ "") do
    if what == "", do: what = "*"
    {order_by_sql, order_by_args} = order_by(args)
    args = Keyword.delete(args,:order_by)
    if (order_by_sql == "" and default_order_by != "") do
      {order_by_sql, order_by_args} = order_by(order_by: default_order_by)
    end
    
    {limit_sql, limit_args} = limit(args)
    args = Keyword.delete(args,:limit)

    {group_by_sql, group_by_args} = group_by(args)
    args = Keyword.delete(args,:group_by)
    
    {where_sql, where_args} = where(args)
    
    sql = "SELECT #{what} FROM #{table} #{where_sql} #{group_by_sql} #{order_by_sql} #{limit_sql}"
    sql_args = List.flatten(where_args ++ group_by_args ++ order_by_args ++ limit_args)
    {sql, sql_args}
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
        {"ORDER BY " <> args[:order_by],[]}
      else
        {"", []}
      end
    else
      {"", []}
    end
  end

  def group_by(args \\ []) do
    if Keyword.has_key?(args,:group_by) do
      if args[:group_by] != "" && is_binary(args[:group_by]) do
        {"GROUP BY " <> args[:group_by],[]}
      else
        {"", []}
      end
    else
      {"", []}
    end
  end
end
