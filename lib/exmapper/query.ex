defmodule Exmapper.Query do
  defmacro __using__(table) do
    quote do
      require Logger

      @table unquote(table)

      defp generate_query(:create, args, {where_sql, where_args}) do
        args = Keyword.delete(args,:id)
        keys = Keyword.keys(args)
        qmark = Enum.join(List.duplicate(["?"],Enum.count(Keyword.values(args))),",")
        {"INSERT INTO #{@table} (#{Enum.join(keys,",")}) VALUES (#{qmark})", List.flatten(Keyword.values(args))}
      end

      defp generate_query(:update, args, {where_sql, where_args}) do
        set = Enum.join(Enum.map(Keyword.delete(args,:id),fn({key,val}) -> "#{key} = ?" end),", ")
        {"UPDATE #{@table} SET #{set} #{where_sql}", List.flatten(Keyword.values(Keyword.delete(args,:id)))++where_args}
      end

      defp generate_query(:delete, {where_sql, where_args}) do
        {"DELETE FROM #{@table} #{where_sql}", where_args}
      end


      defp where_transform(type, value) when type in ["in"] and is_map(value) do 
          {select_sql, select_args} = select(value.select, value.from, value.where)
          [type,"(" <> select_sql <> ")", select_args]
      end
      defp where_transform(type, value) when type in ["in"] and is_list(value) do 
          [type,"(" <> Enum.join(Enum.map(value, fn(_v) -> "?" end),",") <> ")", value]
      end
      
      defp where_transform(type, value) when type in ["<","<=",">",">="] do
        [type, "?", value]
      end

      defp where_transform("gt", value), do: [">","?", value]
      defp where_transform("gte", value), do: [">=","?", value]
      defp where_transform("lt", value), do: ["<","?", value]
      defp where_transform("lte", value), do: ["<=","?", value]
      defp where_transform("like", value), do: ["LIKE","?", value]
      defp where_transform(_, value), do: ["=","?", value]
      
      defp select(what, table, args, default_order_by \\ "") do
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

      defp build_where([], "AND"), do: {"", []}
      defp build_where([], "OR"), do: {"", []}
      defp build_where(args, joiner) do
        {ret, values} = Enum.map_reduce args, [], fn({key,value}, acc) ->
          key = Atom.to_string(key)
          case key do
            "and" -> 
              {sql_str, vals} = build_where(value, "AND")
              {sql_str, acc ++ vals}
            "or" -> 
              {sql_str, vals} = build_where(value, "OR")
              {sql_str, acc ++ vals}
             _ ->
              oper = List.last(String.split(key,"."))
              key = String.replace(key, ".#{oper}","")
              [mark, qm , value] = where_transform(oper, value)
              { "#{key} #{mark} #{qm}", acc ++ [value]}
          end
        end
        {"(" <> (ret |> Enum.join(" #{joiner} ")) <> ")", values}
      end

      defp where([]), do: {"",[]}
      defp where(args) do
        {where_sql, where_args} = build_where(args, "AND")
        {"WHERE " <> where_sql, where_args}
      end
      
      defp limit(args \\ []) do
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
      
      defp order_by(args \\ []) do
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
     end
  end
end
