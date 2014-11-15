defmodule Exmapper.Query do
  defmacro __using__(table) do
    quote do
      require Logger

      @table unquote(table)

      def generate_query(:create, args, {where_sql, where_args}) do
        args = Keyword.delete(args,:id)
        keys = Keyword.keys(args)
        qmark = Enum.join(List.duplicate(["?"],Enum.count(Keyword.values(args))),",")
        {"INSERT INTO #{@table} (#{Enum.join(keys,",")}) VALUES (#{qmark})", List.flatten(Keyword.values(args))}
      end

      def generate_query(:update, args, {where_sql, where_args}) do
        set = Enum.join(Enum.map(Keyword.delete(args,:id),fn({key,val}) -> "#{key} = ?" end),", ")
        {"UPDATE #{@table} SET #{set} #{where_sql}", List.flatten(Keyword.values(Keyword.delete(args,:id)))++where_args}
      end

      def generate_query(:delete, args, {where_sql, where_args}) do
        
      end

    end
  end
end
