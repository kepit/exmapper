defmodule Exmapper.Model do
  import Exmapper.Query

  defmacro __using__(opts) do
    quote do
      require Exmapper.Field
      import Exmapper.Schema
      require Logger
      use Timex

      use Exmapper.Callbacks
      
      repo = :default
      load_assoc = true
      unless is_nil(unquote(opts)[:repo]), do: repo = unquote(opts)[:repo]
      unless is_nil(unquote(opts)[:load_assoc]), do: load_assoc = unquote(opts)[:load_assoc]

      @repo repo
      @load_assoc load_assoc
      @before_compile Exmapper.Model

      def load_assoc, do: @load_assoc
      def repo, do: @repo

      defp table_name() do
        Atom.to_string(__table_name__)
      end

      defp to_new(args) when is_tuple(args), do: args |> elem(1) |> to_new
      defp to_new(args) when is_list(args), do: Enum.map(args, fn(a) -> new(a) end)
      defp to_new(args) when is_nil(args), do: nil

      def new(params \\ []) do
        params = Exmapper.Utils.keys_to_atom(params)
        Enum.reduce Map.to_list(__struct__), __struct__, fn({key,val}, acc) ->
          field = __fields__[key]
          unless load_assoc == false && (field[:type] == :belongs_to || field[:type] == :has_many) do
            unless is_nil(params[key]), do: val = params[key]
            data = Exmapper.Field.Transform.decode(field[:type], params, field, key, val)
            Map.put(acc,key,data)
          else
            acc
          end
        end
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

      def execute!(sql, args \\ []), do: query!(sql, args) |> result_to_keywords

      def raw(field \\ "*",args \\ []), do: select(field, table_name, Exmapper.Field.Transform.encode_args(__fields__,args), "id ASC") |> query |> elem(1) |> Exmapper.Utils.to_map
      def all(args \\ []), do: select("*", table_name, Exmapper.Field.Transform.encode_args(__fields__,args), "id ASC") |> query |> to_new
      def count(args \\ []), do: select("COUNT(*)", table_name, Exmapper.Field.Transform.encode_args(__fields__,args)) |> query |> elem(1) |> List.first |> List.first |> elem(1)
      def first(args \\ []), do: select("*", table_name, Keyword.merge([limit: 1],Exmapper.Field.Transform.encode_args(__fields__,args)), "id ASC") |> query |> to_new |> List.first
      def last(args \\ []), do: select("*", table_name, Keyword.merge([limit: 1],Exmapper.Field.Transform.encode_args(__fields__,args)), "id DESC") |> query |> to_new |> List.first
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
        case run_callbacks(__MODULE__, :before, type, args) do
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

            case query(build_query(type, table_name, args, where)) do
              {:ok, data} ->
                id = data[:insert_id]
                if id == 0 && !is_nil(args[:id]), do: id = args[:id]
                data = get(id)
                case run_callbacks(__MODULE__, :after, type, data) do
                  {:ok, data} ->
                    {:ok, data}
                  _ -> {:error, :after_callback}
                end
                
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
        case run_callbacks(__MODULE__, :before, :delete, args) do
          {:ok, args} ->
            case query(build_query(:delete, table_name,  where(id: args.id))) do
              {:ok, _} ->
                run_callbacks(__MODULE__, :after, :delete, args)
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

  defmacro __before_compile__(_env) do
    quote bind_quoted: [] do
      Enum.filter_map(@fields,fn({k,v}) -> (v[:type] == :has_many or v[:type] == :belongs_to) end, fn({k,v}) ->
        case v[:type] do
          :has_many ->
            def unquote(:"#{k}!")(model, query_type \\ :all, opts \\ []) do
              Exmapper.Associations.has_many(unquote(v),model,query_type,opts)
            end
            :belongs_to ->
            def unquote(:"#{k}!")(model) do
              Exmapper.Associations.belongs_to(unquote(v),model)
            end
        end

      end)
      
    end
  end
  
end
