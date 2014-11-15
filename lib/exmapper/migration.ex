defmodule Exmapper.Migration do

  require Logger

  @field_types [string: "VARCHAR(255)", integer: "INT", text: "TEXT", float: "FLOAT", double: "DOUBLE", boolean: "TINYINT(1)", datetime: "DATETIME", json: "TEXT"]
  
  defp fields_to_mysql(collection,joiner,fun) do
    Enum.join(Enum.reject(Enum.map(collection,fn({key,val}) ->
                                     if !Exmapper.is_virtual_type(val[:type]) do
                                       default = ""
                                       primary_key = ""
                                       auto_increment = ""
                                       not_null = "NULL "
                                       if val[:opts][:primary_key] == true, do: primary_key = "PRIMARY KEY"
                                       if val[:opts][:required] == true, do: not_null = "NOT NULL "
                                       if val[:opts][:auto_increment] == true, do: auto_increment = "AUTO_INCREMENT "
                                       if val[:opts][:default] != nil && !is_function(val[:opts][:default]), do: default = "DEFAULT #{val[:opts][:default]} "
                                       type = @field_types[val[:type]]
                                       if type == nil, do: type = @field_types[:string]
                                       cond do
                                         val[:type] == :string ->
                                           if val[:opts][:default] != nil, do: default = "DEFAULT '#{val[:opts][:default]}'"
                                           val[:type] == :text ->
                                           if val[:opts][:default] != nil, do: default = ""
                                           true -> nil
                                       end
                                       fun.([name: key, type: type, opts: "#{not_null}#{default}#{auto_increment}#{primary_key}"])
                                     else
                                       nil
                                     end
                                   end), &(is_nil(&1))),joiner)
  end

  def migrate(module) do
    fields = fields_to_mysql(module.__fields__,", ",fn(x) -> "#{x[:name]} #{x[:type]} #{x[:opts]}" end)
    case Exmapper.query("CREATE TABLE #{module.__name__}(#{fields})", [], module.repo) do
      {:ok_packet, _, _, _, _, _, _} ->
        alter = Enum.join(List.delete(Enum.map(module.__fields__,fn({key,val}) ->
                                                 if val[:opts][:foreign_key] == true do
                                                   mod = val[:opts][:mod]
                                                   table = mod.__name__
                                                   "ADD CONSTRAINT #{module.__name__}_to_#{table} FOREIGN KEY (#{key}) REFERENCES #{table} (id) ON UPDATE CASCADE ON DELETE CASCADE"
                                                 else
                                                   nil
                                                 end
                                               end),nil)," ")
        if alter == "" do
          true
        else
          case Exmapper.query("ALTER TABLE #{module.__name__} #{alter}", [], module.repo) do
            {:ok_packet, _, _, _, _, _, _} ->
              true
            error ->
              Logger.info inspect error
              false
          end
        end
      error ->
        Logger.info inspect error
        false
    end
  end

  def upgrade(module) do
    old_fields = Enum.map(Exmapper.query("SHOW COLUMNS FROM #{module.__name__}", [], module.repo) |> Exmapper.to_proplist, fn(x) -> String.to_atom(elem(List.first(x),1)) end)
    new_fields = Enum.reject(module.__fields__,fn({k,v}) -> Enum.member?(old_fields,k) || Exmapper.is_virtual_type(v[:type])  end)
    if Enum.count(new_fields) == 0 do
      false
    else
      alters = fields_to_mysql(new_fields," ",fn(x) -> "ADD #{x[:name]} #{x[:type]} #{x[:opts]}" end)
      case Exmapper.query("ALTER TABLE #{module.__name__} #{alters}", [], module.repo) do
        {:ok_packet, _, _, _, _, _, _} ->
          true
        error ->
          Logger.info inspect error
          false
      end 
    end
  end

  def drop(module) do
    case Exmapper.query("DROP TABLE #{module.__name__}", [], module.repo) do
      {:ok_packet, _, _, _, _, _, _} -> true
      error ->
        Logger.info inspect error
        false
    end
  end

end
