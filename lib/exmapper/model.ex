defmodule Exmapper.Model do
  require Exmapper.Field
  
  defmodule Table do

    alias Exmapper.Field

    defmacro before_callback(cmd,fun) do
      quote do: Module.put_attribute(__MODULE__,:befores,Keyword.put(Module.get_attribute(__MODULE__,:befores),:"#{unquote(cmd)}",unquote(fun)))
    end
    defmacro after_callback(cmd,fun) do
      quote do: Module.put_attribute(__MODULE__,:afters,Keyword.put(Module.get_attribute(__MODULE__,:afters),:"#{unquote(cmd)}",unquote(fun)))
    end
      
    defmacro before_create(fun), do: quote do: before_callback(:create, unquote(fun))
    defmacro before_delete(fun), do: quote do: before_callback(:delete, unquote(fun))
    defmacro before_update(fun), do: quote do: before_callback(:update, unquote(fun))
    defmacro after_create(fun), do: quote do: after_callback(:create, unquote(fun))
    defmacro after_delete(fun), do: quote do: after_callback(:delete, unquote(fun))
    defmacro after_update(fun), do: quote do: after_callback(:update, unquote(fun))

    defmacro schema(name,[do: block]) do

      if is_binary(name), do: name = String.to_atom(name)
      if is_list(name), do: name = List.to_atom(name)

      quote do
        import Exmapper.Field
        use Timex

        @fields []
        @befores [delete: nil, create: nil, update: nil]
        @afters [delete: nil, create: nil, update: nil]
        @name unquote(name)

        use Exmapper.Query, @name

        field :id, :integer, primary_key: true, auto_increment: true, required: true
        unquote(block)
              
        defstruct Enum.map(@fields, fn({key,val}) -> {key,val[:opts][:default]} end)

        def new(params \\ []) do
          struct = %__MODULE__{}
          params = Enum.map(params,fn({k,v}) ->
                              if is_binary(k) do
                                {String.to_atom(k),v}
                              else
                                {k,v}
                              end
                            end)
          rec = Map.to_list(struct)

          Enum.reduce rec, struct, fn({key,val}, acc) ->
            field = __fields__[key]
            unless is_nil(params[key]), do: val = params[key]
            data = Field.Transform.decode(field[:type], params, field, key, val)
            Map.put(acc,key,data)
          end

        end


     

        def __befores__, do: @befores
        def __afters__, do: @afters
        def __name__, do: @name
        def __fields__, do: @fields
      end
    end
  end

  

  defmacro __using__(opts) do
    quote do
      import Table
      require Logger

      repo = :default
      unless is_nil(unquote(opts)[:repo]), do: repo = unquote(opts)[:repo]
      @repo repo

      def repo do
        @repo
      end

      def run_callbacks(callbacks, type, args) do
        if callbacks[type] != nil do 
          cb = callbacks[type]
          if is_atom(cb) do
            apply(__MODULE__, cb, [args])
          else
            callbacks[type].(args)
          end
        else
          {:ok, args}
        end
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

      def to_keywords(value), do: Exmapper.to_keywords(value)

      def all(args \\ []), do: select("*", table_name, args, "id ASC") |> Exmapper.query(@repo) |> to_new
      def count(args \\ []), do: select("COUNT(*)", table_name, args) |> Exmapper.query(@repo) |> elem(1) |> List.first |> List.first |> elem(1)
      def first(args \\ []), do: select("*", table_name, Keyword.merge([limit: 1],args), "id ASC") |> Exmapper.query(@repo) |> to_new |> List.first
      def last(args \\ []), do: select("*", table_name, Keyword.merge([limit: 1],args), "id DESC") |> Exmapper.query(@repo) |> to_new |> List.first
      def get(id), do: select("*", table_name, [id: id]) |> Exmapper.query(@repo) |> to_new |> List.first
      
      def create!(args), do: elem(create(args),1)
      def create(args) when is_list(args), do: create_or_update(:create, new(args), {"",[]})
      def create(args) when is_map(args), do: create_or_update(:create, Map.merge(new(), args), {"",[]})
      
      def update!(args), do: elem(update(args),1)
      def update(args) when is_map(args), do: create_or_update(:update, args, Exmapper.where(id: args.id))

      defp create_or_update(type, args, where \\ {"",[]}) do
        case run_callbacks(__MODULE__.__befores__, type, args) do
          {:ok, args} ->
            args = Enum.reject(
              Enum.map(Map.from_struct(args),fn({key,val}) ->
                         if __fields__[key][:opts][:required] == true && val == nil && key != :id, do: raise("Field #{key} is required!")
                         case Exmapper.is_virtual_type(__fields__[key][:type]) do
                           false -> Exmapper.Field.Transform.encode(__fields__[key][:type], key, val)
                           true -> nil
                         end
                       end),fn(x) -> is_nil(x) end)
            case Exmapper.query(generate_query(type, args, where), @repo) do
              {:ok, data} ->
                id = data[:insert_id]
                if id == 0 && !is_nil(args[:id]), do: id = args[:id]
                data = get(id)
                run_callbacks(__MODULE__.__afters__, type, data)
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
        case run_callbacks(__MODULE__.__befores__, :delete, args) do
          {:ok, args} ->
            case Exmapper.query(generate_query(:delete, Exmapper.where(id: args.id)), @repo) do
              {:ok, _} ->
                run_callbacks(__MODULE__.__afters__, :delete, args)
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
