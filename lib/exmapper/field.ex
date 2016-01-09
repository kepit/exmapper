defmodule Exmapper.Field do


  def timestamps_create_callback_integer(data) do
    Map.put(data, :created_at, Timex.Date.to_secs(Timex.Date.local)) |> timestamps_update_callback_integer
  end
  def timestamps_create_callback_datetime(data) do
    Map.put(data, :created_at, Timex.Date.local) |> timestamps_update_callback_datetime
  end
  def timestamps_update_callback_integer(data) do
    Map.put(data, :updated_at, Timex.Date.to_secs(Timex.Date.local))
  end
  def timestamps_update_callback_datetime(data) do
    Map.put(data, :updated_at, Timex.Date.local)
  end

  defmacro field(name,type \\ :string,opts \\ []) do
    quote do
      fields = Module.get_attribute(__MODULE__,:fields)
      field = Keyword.new([{unquote(name), [name: unquote(name), type: unquote(type), opts: unquote(opts)]}])
      Module.put_attribute(__MODULE__,:fields,fields++field)
    end
  end

  defmacro timestamps(type, _opts \\ []) do
    create_fun = String.to_atom("timestamps_create_callback_#{type}")
    update_fun = String.to_atom("timestamps_update_callback_#{type}")
    quote do
      field :created_at, unquote(type)
      field :updated_at, unquote(type)
      before_create Exmapper.Field, unquote(create_fun)
      before_update Exmapper.Field, unquote(update_fun)
    end
  end
  
  defmacro belongs_to(name,mod,opts \\ []) do
    quote do
      parent_field = :"#{unquote(name)}_id"
      field = Keyword.new([{parent_field, [name: parent_field, type: :integer, opts: [foreign_key: true, mod: unquote(mod), required: true]]}])
      virt = Keyword.new([{:"#{unquote(name)}", [name: :"#{unquote(name)}", type: :belongs_to, opts: unquote(opts) ++ [parent_field: parent_field, mod: unquote(mod)]]}])
      fields = Module.get_attribute(__MODULE__,:fields)
      Module.put_attribute(__MODULE__,:fields,fields++field++virt)
    end
  end
  
  defmacro has_many(name,mod, opts \\ []) do
    quote do
      foreign_key = unquote(opts[:foreign_key]) || Exmapper.Utils.module_to_id(__MODULE__)
      field = Keyword.new([{:"#{unquote(name)}", [name: :"#{unquote(name)}", type: :has_many, opts: unquote(opts) ++ [foreign_key: foreign_key, mod: unquote(mod)]]}])
      fields = Module.get_attribute(__MODULE__,:fields)
      Module.put_attribute(__MODULE__,:fields,fields++field)
    end               
  end

  defmodule Transform do

    def encode_args(fields, args) do
      Enum.map args, fn({key,value}) ->
        field = fields[:"#{List.first(String.split(Atom.to_string(key),"."))}"]
        if is_list(value) and field[:type] != :flag do
          {key, Enum.map(value,fn(x) -> elem(encode(field[:type], key, x, field),1) end)}
        else
          encode(field[:type], key, value, field)
        end
      end
    end
    
    def encode(:boolean, key, val, _) do
      retval = case val == true do
        true -> 1
        false -> 0
      end
      {key, retval}
    end

    def encode(:datetime, key, val, _) do
      #{key, {{val.year,val.month,val.day},{val.hour,val.minute,val.second,0}}}
      {key, {{val.year,val.month,val.day},{val.hour,val.minute,val.second}}}
    end

    def encode(:json, key, val, _) when is_map(val) do
      {key, Json.encode!(val)}
    end

    def encode(:enum, key, val, field) when is_atom(val) do
      enums = field[:opts][:values]
      retval = Enum.find_index(enums, fn(x) -> x == val end)
      if is_nil(retval) do
        #retval = nil
        retval = :undefined
      end
      {key, retval}
    end

    def encode(:enum, key, val, field) when is_bitstring(val) do
      encode(:enum, key, String.to_atom(val), field)
    end
    

    def encode(:flag, key, val, field) when is_list(val) do
      flags = field[:opts][:values]
      val = Enum.map(val, fn(v) ->
                       if is_atom(v) do v else String.to_atom(v) end
                     end)
      retval = Enum.map(flags, fn(t) -> 
                        if Enum.member?(val, t) do
                          "1"
                        else
                          "0"
                        end
                        end) |> Enum.join |> String.reverse |> String.to_integer(2)
      {key, retval}
    end

    def encode(:flag, key, val, field) when is_atom(val) do
      encode(:flag, key, [val], field)
    end
    
    
    def encode(type, key, val, _) when is_list(val) and type in [:string, :text] and not is_nil(val) do
      { key, List.to_string(val) }
    end
    
    def encode(type, key, val, _) when is_atom(val) and type in [:string, :text] and not is_nil(val) do
      { key, Atom.to_string(val) }
    end

    def encode(_ ,key, _val, _) when is_nil(_val) do
#      {key, nil} #:undefined
      {key, :undefined}
    end

    def encode(_, key, val, _) do
      { key, val } 
    end

    def decode(:belongs_to, params, field, _key, val) do
      id = params[field[:opts][:parent_field]]
      if id != nil do
        (fn() ->
          Exmapper.Associations.belongs_to(field,params)
         end)
      else
        val
      end
      
    end

    def decode(_, _, _, _, :undefined) do
      nil
    end

    def decode(:string, _, _, _, :undefined) do
      nil
    end

    def decode(:text, _, _, _, :undefined) do
      nil
    end

    def decode(:enum, _params, field, _key, val) when is_integer(val) do
      enums = field[:opts][:values]
      Enum.at(enums, val, nil)
    end

    def decode(:enum, _params, _field, _key, val) when is_atom(val) do
      val
    end

    def decode(:flag, _params, field, _key, val) when is_integer(val) do
      flags = Enum.with_index(field[:opts][:values])
      str = Integer.to_string(val, 2) |> String.reverse
      Enum.filter_map(flags, fn({_, i}) -> String.at(str, i) == "1" end, fn({t,_}) -> t end)
    end
    
    def decode(:has_many, params, field, _key, _val) do
        (fn(args) ->
          cond do
            is_list(args) -> Exmapper.Associations.has_many(field,params,Enum.at(args,0),Enum.slice(args,1..-1))
            true -> Exmapper.Associations.has_many(field,params,args)
          end
        end)     
    end

    def decode(:json, _params, _field, _key, val) do
      case val do
        nil -> nil
        _ ->
          {_, data} = Json.decode(val)
          data
      end
    end

    def decode(:boolean, _params, _field, _key, val) do
      val == 1
    end
    
    def decode(:datetime, _params, _field, _key, val) do
      if is_tuple(val) && elem(val,0) == :datetime do
        Timex.Date.from(elem(val,1),:local)
      else
        if is_nil(val) do
          Timex.Date.from({{0,0,0},{0,0,0}}, :local)
        else
          if is_tuple(val) do
            Timex.Date.from(val, :local)
          else
            val
          end
        end
      end
    end

    def decode(_, _params, _field, _key, val) do
      if is_function(val) do
        val.()
      else
        val
      end
    end
  end
end
