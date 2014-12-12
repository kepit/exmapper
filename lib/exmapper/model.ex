defmodule Exmapper.Model do
  require Exmapper.Field

  defmacro __using__(opts) do
    quote do
      import Exmapper.Table
      require Logger

      repo = :default
      unless is_nil(unquote(opts)[:repo]), do: repo = unquote(opts)[:repo]
      @repo repo
      def repo, do: @repo

      def run_callbacks(callbacks, type, args) do
        ret = Enum.reduce callbacks[type], args, fn(cb, acc) ->
          case cb do
            callback when is_atom(callback) -> apply(__MODULE__, callback, [acc])
            callback -> callback.(acc)
          end
        end
        {:ok, ret}
      end

      defp table_name() do
        Atom.to_string(__name__)
      end

      defp to_new(args) when is_tuple(args) do
        args |> elem(1) |> to_new
      end
      defp to_new(args) when is_list(args) do
        Enum.map args, fn(a) -> new(a) end
      end
      defp to_new(args) when is_nil(args) do
        nil
      end

      def migrate, do: Exmapper.Migration.migrate(__MODULE__)
      def upgrade, do: Exmapper.Migration.upgrade(__MODULE__)
      def drop, do: Exmapper.Migration.drop(__MODULE__)

      def to_keywords(value), do: Exmapper.Utils.to_keywords(value)

      def result_to_keywords(value) do
        Enum.map value, fn(v) ->
          Keyword.new(v, fn({x,y}) -> {String.to_atom(x),y} end)
        end
      end

      def query({query,args}), do: query(query, args)
      def query(query, args), do: Exmapper.Adapter.query(query, args, @repo)
      def query!({query,args}), do: query!(query, args)
      def query!(query, args) do
        {:ok, data} = query(query, args)
        data
      end

      def execute(sql, args \\ []) do
        {state, data} = query(sql, args)
        if state == :ok do
          {:ok, data |> result_to_keywords}
        else
          {state, data}
        end
      end

      def execute!(sql, args \\ []) do
        query!(sql, args) |> result_to_keywords
      end


      def all(args \\ []), do: select("*", table_name, args, "id ASC") |> query |> to_new
      def count(args \\ []), do: select("COUNT(*)", table_name, args) |> query |> elem(1) |> List.first |> List.first |> elem(1)
      def first(args \\ []), do: select("*", table_name, Keyword.merge([limit: 1],args), "id ASC") |> query |> to_new |> List.first
      def last(args \\ []), do: select("*", table_name, Keyword.merge([limit: 1],args), "id DESC") |> query |> to_new |> List.first
      def get(id), do: select("*", table_name, [id: id]) |> query |> to_new |> List.first
      
      def create!(args), do: elem(create(args),1)
      def create(args) when is_list(args), do: create_or_update(:create, new(args), {"",[]})
      def create(args) when is_map(args), do: create_or_update(:create, Map.merge(new(), args), {"",[]})
      
      def update!(args), do: elem(update(args),1)
      def update(args) when is_list(args) do
        struct = get(args[:id])
        if is_nil(struct), do: raise("Entry not found")
        args = Keyword.delete(args,:id)
        update(Enum.reduce(Map.from_struct(struct), struct, fn({key,val},acc) ->
                                          unless(is_nil(args[key]), do: acc = Map.put(acc, key, args[key]))
                                          acc
                                        end))
      end
      def update(args) when is_map(args), do: create_or_update(:update, args, where(id: args.id))



      defp create_or_update(type, args, where \\ {"",[]}) do
        case run_callbacks(__MODULE__.__before_callbacks__, type, args) do
          {:ok, args} ->
            args = Enum.reject(
              Enum.map(Map.from_struct(args),fn({key,val}) ->
                         field = __fields__[key]
                         if field[:opts][:required] == true && val == nil && key != :id, do: raise("Field #{key} is required!")
                         case Exmapper.Utils.is_virtual_type(field[:type]) do
                           false -> Exmapper.Field.Transform.encode(field[:type], key, val, field)
                           true -> nil
                         end
                       end),fn(x) -> is_nil(x) end)
            case query(generate_query(type, args, where)) do
              {:ok, data} ->
                id = data[:insert_id]
                if id == 0 && !is_nil(args[:id]), do: id = args[:id]
                data = get(id)
                run_callbacks(__MODULE__.__after_callbacks__, type, data)
                {:ok, data}
              error ->
                Logger.info inspect error
                {:error, error}
            end
          _ -> {:error, :before_callback}
        end
      end
      
      def delete!(args), do: elem(delete(args),1)
      def delete(args) when is_list(args), do: delete(first(args))
      def delete(args) when is_nil(args), do: {:error, :not_found}
      def delete(args) when is_map(args) do
        case run_callbacks(__MODULE__.__before_callbacks__, :delete, args) do
          {:ok, args} ->
            case query(generate_query(:delete, where(id: args.id))) do
              {:ok, _} ->
                run_callbacks(__MODULE__.__after_callbacks__, :delete, args)
                {:ok, :success}
              error ->
                Logger.info inspect error
                {:error, error}
            end
          _ -> {:error, :before_callback}
        end
      end
    end
  end

end
