defmodule Exmapper.Field do

  defmacro field(name,type \\ :string,opts \\ []) do
    quote do
      fields = Module.get_attribute(__MODULE__,:fields)
      field = Keyword.new([{unquote(name), [name: unquote(name), type: unquote(type), opts: unquote(opts)]}])
      setter_field = Keyword.new([{:"#{unquote(name)}!", [name: unquote(name), type: :setter, opts: [mod: __MODULE__]]}])
      Module.put_attribute(__MODULE__,:fields,fields++field++setter_field)
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
      foreign_key = unquote(opts[:foreign_key]) || Exmapper.module_to_id(__MODULE__)
      field = Keyword.new([{:"#{unquote(name)}", [name: :"#{unquote(name)}", type: :has_many, opts: unquote(opts) ++ [foreign_key: foreign_key, mod: unquote(mod)]]}])
      fields = Module.get_attribute(__MODULE__,:fields)
      Module.put_attribute(__MODULE__,:fields,fields++field)
    end               
  end


  defmodule Transform do
    
    def main_encode(val) when is_boolean(val) do
      if val == true do
        1
      else
        0
      end
    end

    def main_encode(val) do
      val
    end

    def decode(:setter, params, field, key, val) do
      fn(new_val) ->
        mod = field[:opts][:mod]
        if is_nil(params[:id]) do
          mod.new(Keyword.put(params, field[:name], new_val))
        else
          mod.update(mod.new(Keyword.put(params, field[:name], new_val)))
        end
      end

    def encode(:boolean, key, val) do
      retval = case val == true do
        true -> 1
        false -> 0
      end
      {key, retval}
    end

    def encode(:datetime, key, val) do
      {key, {{val[:year],val[:month],val[:day]},{val[:hour],val[:minute],val[:second]}}}
    end

    def encode(:json, key, val) when is_map(val) do
      {key, JSEX.encode!(val)}
    end

    def encode(_, key, val) do
      { key, val } 
    end

    def decode(:belongs_to, params, field, key, val) do
      id = params[field[:opts][:parent_field]]
      if id != nil do
        mod = field[:opts][:mod]
        (fn() ->
           mod.get(id)
         end)
      else
        val
      end
    end
    
    def decode(:has_many, params, field, key, val) do
      if params[:id] != nil do
        mod = field[:opts][:mod]
        through = field[:opts][:through]
        foreign_key = field[:opts][:foreign_key]
        (fn(args) ->
           query = Keyword.new([{foreign_key, params[:id]}])
           if through != nil do
             assoc_args = query |>
               Keyword.put(:order_by, Atom.to_string(foreign_key))
             assoc = through.all(assoc_args)
             assoc_mod_id = Exmapper.module_to_id(mod)
             ids = Enum.map assoc, fn(a) ->
               Map.get(a,assoc_mod_id)
             end
             query = Keyword.new([{String.to_atom("id.in"), ids}])
           end
           if is_list(args) do
             type = Enum.at(args,0)
             args = Enum.drop(args,1) ++ query
           else
             type = args
             args = query
           end
           apply(mod, type, [args])
          end)
      else
        val
      end          
    end

    def decode(:json, _params, _field, _key, val) do
      JSEX.decode!(val)
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
          val
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
