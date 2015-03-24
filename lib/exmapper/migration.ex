defmodule Exmapper.Migration do

  require Logger

  @field_types [string: "VARCHAR(255)", integer: "INT(11)", text: "TEXT", float: "FLOAT", double: "DOUBLE", boolean: "TINYINT(1)", datetime: "DATETIME", json: "TEXT", enum: "INT(11)", blob: "BLOB", flag: "INT(11)"]

  defp field_to_mysql(key,val,fun) do
    if !Exmapper.Utils.is_virtual_type(val[:type]) do
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
      case val[:type] do
        :string ->
          if val[:opts][:default] != nil && !is_function(val[:opts][:default]), do: default = "DEFAULT '#{val[:opts][:default]}'"
        :text ->
          if val[:opts][:default] != nil, do: default = ""
        :enum ->
          if is_atom(val[:opts][:default]) do
            idx = Enum.find_index(val[:opts][:values], fn(x) -> x == val[:opts][:default] end)
            if idx > -1, do: default = "DEFAULT #{idx}"
          end
        true -> nil
        end
      fun.([name: key, type: type, opts: "#{not_null}#{default}#{auto_increment}#{primary_key}"])
    else
      nil
    end
  end
  
  defp fields_to_mysql(collection,joiner,fun) do
    Enum.reduce(collection,"",fn({key,val},acc) ->
      result = field_to_mysql(key,val,fun)
      cond do
        is_nil(result) -> acc
        acc == "" -> acc <> result
        true -> acc <> joiner <> result
      end
    end)
  end

  defp create_foreign_keys(module, [{key,val}|tail]) do
    if val[:opts][:foreign_key] == true do
      table = val[:opts][:mod].__table_name__
      alter = "CONSTRAINT #{module.__table_name__}_to_#{table} FOREIGN KEY (#{key}) REFERENCES #{table} (id) ON UPDATE CASCADE ON DELETE CASCADE"
      case Exmapper.Adapter.query("ALTER TABLE #{module.__table_name__} ADD #{alter}", [], module.repo) do
        {:error, error} ->
          Logger.info inspect error
          false
        _ -> create_foreign_keys(module,tail)
      end
    else
      create_foreign_keys(module,tail)
    end
  end
  defp create_foreign_keys(_, []), do: true

  defp update_fields(module,[{field,opts}|tail]) do
    alter = field_to_mysql(field, opts, fn(x) -> "#{x[:name]} #{x[:type]} #{x[:opts]}" end)
    case Exmapper.Adapter.query("ALTER TABLE #{module.__table_name__} MODIFY #{alter}", [], module.repo) do
      {:error, error} ->
        Logger.info inspect error
        {:error, error}
      _ -> update_fields(module,tail)
    end
  end
  defp update_fields(_,[]), do: :ok

  defp create_new_fields(module,[{field,opts}|tail]) do
    alter = field_to_mysql(field, opts, fn(x) -> "#{x[:name]} #{x[:type]} #{x[:opts]}" end)
    Logger.warn inspect alter
    case Exmapper.Adapter.query("ALTER TABLE #{module.__table_name__} ADD #{alter}", [], module.repo) do
      {:error, error} ->
        Logger.info inspect error
        {:error, error}
      _ -> create_new_fields(module,tail)
    end
  end
  defp create_new_fields(_,[]), do: :ok

  defp get_fields({:ok, columns}) do
    fields = Enum.reduce(columns, %{names: [], types: %{}}, fn(x,acc) ->
      field = Enum.into(x,%{})
      name = String.to_atom(field["Field"])
      %{acc | names: acc.names ++ [name], types: Map.put(acc.types,name,String.upcase(field["Type"]))}
    end)
  end
  defp get_fields({:error, error}) do
    Logger.warn inspect error
    %{names: [], types: %{}}
  end
  defp get_fields(_), do: %{names: [], types: %{}}
  
  def migrate(module) do
    fields = fields_to_mysql(module.__fields__,", ",fn(x) -> "#{x[:name]} #{x[:type]} #{x[:opts]}" end)
    case Exmapper.Adapter.query("CREATE TABLE #{module.__table_name__}(#{fields})", [], module.repo) do
      {:ok, _} ->
        create_foreign_keys(module, module.__fields__)
      error ->
        Logger.info inspect error
        false
    end
  end
  
  def upgrade(module) do
    fields = get_fields(Exmapper.Adapter.query("SHOW COLUMNS FROM #{module.__table_name__}", [], module.repo))
    new_fields = Enum.reject(module.__fields__,fn({k,v}) ->
      Enum.member?(fields.names,k) || Exmapper.Utils.is_virtual_type(v[:type])
    end)
    update_fields = Enum.reject(module.__fields__,fn({k,v}) ->
      !Enum.member?(fields.names,k) || @field_types[v[:type]] == fields.types[k]
    end)
    %{new_fields: create_new_fields(module,new_fields), update_fields: update_fields(module, update_fields)}
  end

  def drop(module) do
    case Exmapper.Adapter.query("DROP TABLE #{module.__table_name__}", [], module.repo) do
      {:ok, _} -> true
      error ->
        Logger.info inspect error
        false
    end
  end

end
