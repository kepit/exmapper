defmodule Exmapper.Field do

  defmacro field(name,type \\ :string,opts \\ []) do
    quote do
      fields = Module.get_attribute(__MODULE__,:fields)
      field = Keyword.new([{unquote(name), [name: unquote(name), type: unquote(type), opts: unquote(opts)]}])
      setter_field = Keyword.new([{:"#{unquote(name)}!", [name: unquote(name), type: :setter, opts: [mod: __MODULE__, original_type: unquote(type), original_opts: unquote(opts)]]}])
      Module.put_attribute(__MODULE__,:fields,fields++field++setter_field)
    end
  end

  defmacro timestamps(type, _opts \\ []) do
    quote do
      field :created_at, unquote(type)
      field :updated_at, unquote(type)

      before_create :__timestamps_callback_create__
      before_update :__timestamps_callback_update__

      def __timestamps_callback_create__(data) do
        field_type = __fields__[:created_at][:type]
        ret = case field_type do
          :integer -> data.created_at!.(Timex.Date.convert(Timex.Date.local, :secs))
          :datetime -> data.created_at!.(Timex.Date.local)
          _ -> data
        end
        __timestamps_callback_update(ret)
      end

      def __timestamps_callback_update__(data) do
        field_type = __fields__[:updated_at][:type]
        case field_type do
          :integer -> data.updated_at!.(Timex.Date.convert(Timex.Date.local, :secs))
          :datetime -> data.updated_at!.(Timex.Date.local)
          _ -> data
        end
      end
    end
  end
  
  defmacro belongs_to(name,mod,opts \\ []) do
    quote do
      parent_field = :"#{unquote(name)}_id"
      field = Keyword.new([{parent_field, [name: parent_field, type: :integer, opts: [foreign_key: true, mod: unquote(mod), required: true]]}])
      setter_field = Keyword.new([{:"#{parent_field}!", [name: parent_field, type: :setter, opts: [mod: __MODULE__, original_type: :integer]]}])
      virt = Keyword.new([{:"#{unquote(name)}", [name: :"#{unquote(name)}", type: :belongs_to, opts: unquote(opts) ++ [parent_field: parent_field, mod: unquote(mod)]]}])
      fields = Module.get_attribute(__MODULE__,:fields)
      Module.put_attribute(__MODULE__,:fields,fields++field++setter_field++virt)
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

    def encode(:boolean, key, val, _) do
      retval = case val == true do
        true -> 1
        false -> 0
      end
      {key, retval}
    end

    def encode(:datetime, key, val, _) do
      {key, {{val[:year],val[:month],val[:day]},{val[:hour],val[:minute],val[:second]}}}
    end

    def encode(:json, key, val, _) when is_map(val) do
      {key, JSEX.encode!(val)}
    end

    def encode(:enum, key, val, field) when is_atom(val) do
      enums = field[:opts][:values]
      retval = Enum.find_index(enums, fn(x) -> x == val end)
      {key, retval}
    end

    def encode(:string, key, val, _) when is_nil(val) do
      {key, :undefined}
    end

    def encode(:text, key, val, _) when is_nil(val) do
      {key, :undefined}
    end


    def encode(_ ,key, val, _) when is_nil(val) do
      {key, :undefined}
    end

    def encode(_, key, val, _) do
      { key, val } 
    end


    def decode(:setter, params, field, _key, _val) do
      fn(new_val) ->
        mod = field[:opts][:mod]
        mod.new(Keyword.put(params, field[:name], encode( field[:opts][:original_type],field[:name],new_val, [name: field[:name], type: field[:opts][:original_type], opts: field[:opts][:original_opts]]) |> elem(1)))
      end
    end

    def decode(:belongs_to, params, field, _key, val) do
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

    
    def decode(:has_many, params, field, _key, val) do
      if params[:id] != nil do
        mod = field[:opts][:mod]
        through = field[:opts][:through]
        foreign_key = field[:opts][:foreign_key]
        (fn(args) ->
           query = Keyword.new([{foreign_key, params[:id]}])
           if through != nil do
             assoc_args = query |>
               Keyword.put(:order_by, Atom.to_string(foreign_key))
             through_args = []
             if is_list(args) && is_list(args[:through!]), do: through_args = args[:through!]
             assoc = through.all(assoc_args++through_args)
             assoc_mod_id = Exmapper.module_to_id(mod)
             ids = Enum.map assoc, fn(a) ->
               Map.get(a,assoc_mod_id)
             end
             if Enum.count(ids) == 0 do
               query = ["true": false]
             else
               query = Keyword.new([{String.to_atom("id.in"), ids}])
             end
           end
           if is_list(args) do
             type = Enum.at(args,0)
             args = Enum.drop(args,1) ++ query
           else
             type = args
             args = query
           end
           args = Keyword.delete(args, :through!)
           result = apply(mod, type, [args])
           if through != nil do
             id = cond do
               type in [:create, :update] -> elem(result,1).id
               type in [:"create!", :"update!"] -> result.id
               true -> nil
             end
             unless is_nil(id), do: through.create(["#{Exmapper.module_to_id(mod)}": id, "#{foreign_key}": params[:id]]++through_args)
           end
           result
         end)
      else
        val
      end          
    end

    def decode(:json, _params, _field, _key, val) do
      case val do
        nil -> nil
        _ ->
          {_, data} = JSEX.decode(val)
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
