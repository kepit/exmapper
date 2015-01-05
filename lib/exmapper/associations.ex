defmodule Exmapper.Associations do
  def belongs_to(field, model) do
    mod = field[:opts][:mod]
    id = cond do
      is_map(model) -> Map.get(model,field[:opts][:parent_field],nil)
      is_list(model) -> model[field[:opts][:parent_field]]
      true -> nil
    end
    unless is_nil(id) do
      mod.get(id)
    else
      nil
    end
  end
  
  def has_many(field, model, type, opts \\ []) do
    id = cond do
      is_map(model) -> Map.get(model,:id,nil)
      is_list(model) -> model[:id]
      true -> nil
    end
    unless is_nil(id) do
      mod = field[:opts][:mod]
      through = field[:opts][:through]
      foreign_key = field[:opts][:foreign_key]
      query = Keyword.new([{foreign_key, id}])
      if through != nil do
        assoc_args = query |>
          Keyword.put(:order_by, Atom.to_string(foreign_key))
        through_args = []
        if is_list(opts[:through!]), do: through_args = opts[:through!]
        assoc = through.all(assoc_args++through_args)
        assoc_mod_id = Exmapper.Utils.module_to_id(mod)
        ids = Enum.map assoc, fn(a) ->
          Map.get(a,assoc_mod_id)
        end
        if Enum.count(ids) == 0 do
          query = ["true": false]
        else
          query = Keyword.new([{String.to_atom("id.in"), ids}])
        end
      end
      
      opts = Keyword.delete(opts, :through!) ++ query
      result = apply(mod, type, [opts])
      if through != nil do
        id = cond do
          type in [:create, :update] -> elem(result,1).id
          type in [:"create!", :"update!"] -> result.id
          true -> nil
        end
        unless is_nil(id), do: through.create(["#{Exmapper.Utils.module_to_id(mod)}": id, "#{foreign_key}": id]++through_args)
      end
      result
    else
      nil
    end
  end
end
