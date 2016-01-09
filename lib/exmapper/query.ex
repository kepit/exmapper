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


  defp where_transform(type, value, fields) when type in ["in"] and is_map(value) do 
    {select_sql, select_args} = select(value.select, value.from, value.where, "", fields)
    [type,"(" <> select_sql <> ")", select_args]
  end
  defp where_transform(type, value, _) when type in ["in"] and is_list(value) do 
    [type,"(" <> Enum.join(Enum.map(value, fn(_v) -> "?" end),",") <> ")", value]
  end
  
  defp where_transform(type, value, _) when type in ["<","<=",">",">=","!=","<>"] do
    [type, "?", value]
  end


  defp where_transform("gt", value, _), do: [">","?", value]
  defp where_transform("gte", value, _), do: [">=","?", value]
  defp where_transform("lt", value, _), do: ["<","?", value]
  defp where_transform("lte", value, _), do: ["<=","?", value]
  defp where_transform("like", value, _), do: ["LIKE","?", value]
  defp where_transform(_, value, _), do: ["=","?", value]
  
  defp build_where([], "AND", _), do: {"", []}
  defp build_where([], "OR", _), do: {"", []}
  defp build_where(args, joiner, fields) do
    {ret, values} = Enum.map_reduce args, [], fn({key,value}, acc) ->
      case key do
        :and -> 
          {sql_str, vals} = build_where(value, "AND", fields)
          {sql_str, acc ++ vals}
        :or -> 
          {sql_str, vals} = build_where(value, "OR", fields)
          {sql_str, acc ++ vals}
        _ ->
          field = Keyword.get(fields, key, nil)
          key = Atom.to_string(key)
          oper = List.last(String.split(key,"."))
          key = String.replace(key, ".#{oper}","")
          case field[:type] do
            :flag -> { "(? & #{key}) = ?", acc ++ [value, value]}
            _ -> 
              [mark, qm , value] = where_transform(oper, value, fields)
              { "#{key} #{mark} #{qm}", acc ++ [value]}
          end
          
      end
    end
    {"(" <> (ret |> Enum.join(" #{joiner} ")) <> ")", values}
  end

  def where([], _), do: {"",[]}
  def where(args, fields) do
    {where_sql, where_args} = build_where(args, "AND", fields)
    {"WHERE " <> where_sql, where_args}
  end

  def select(what, table, args, default_order_by \\ "", fields \\ []) do
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
    
    {where_sql, where_args} = where(args, fields)
    
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
