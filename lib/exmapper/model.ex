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
          true
        end
      end

      def migrate, do: Exmapper.Migration.migrate(__MODULE__)
      def upgrade, do: Exmapper.Migration.upgrade(__MODULE__)
      def drop, do: Exmapper.Migration.drop(__MODULE__)

      def to_keywords(value), do: Exmapper.to_keywords(value)

      def all(args \\ []), do: Enum.map(Exmapper.all(Atom.to_string(__name__),args,@repo) |> Exmapper.to_proplist, fn(x) -> new(x) end)
      def count(args \\ []), do: elem(List.first(List.first(Exmapper.count(Atom.to_string(__name__),args,@repo) |> Exmapper.to_proplist)),1)
      def first(args \\ []), do: first_last_get(Exmapper.first(Atom.to_string(__name__),args,@repo) |> Exmapper.to_proplist)
      def last(args \\ []), do: first_last_get(Exmapper.last(Atom.to_string(__name__),args,@repo) |> Exmapper.to_proplist)
      def get(id), do: first_last_get(Exmapper.get(Atom.to_string(__name__),id,@repo) |> Exmapper.to_proplist)

      defp first_last_get(data, reverse \\ false) do
        if Enum.count(data) > 1 do
          if reverse do
            Enum.reverse(Enum.map(data, fn(x) -> new(x) end))
          else
            Enum.map(data, fn(x) -> new(x) end)
          end
        else
          if Enum.count(data) > 0 do
            new(List.first(data))
          else
            nil
          end
        end
      end


      def create(args) when is_map(args) do create(to_keywords(args)) end
      def create(args) when is_list(args) do
        ret = run_callbacks(__MODULE__.__befores__, :create, new(args))
        if ret == false do
          false
        else
          if args[:id] == nil, do: args = Keyword.delete(args,:id)
          args = Enum.reject(
            Enum.map(args,fn({key,val}) ->
                       if __fields__[key][:opts][:required] == true && val == nil, do: raise("Field #{key} is required!")
                       if !Exmapper.is_virtual_type(__fields__[key][:type]) do
                         Field.Transform.encode(__fields__[key][:type], key, val)
                         #if __fields__[key][:type] == :datetime do
                         #  {key, {{val[:year],val[:month],val[:day]},{val[:hour],val[:minute],val[:second]}}}
                         #else
                         #  {key,val}
                         #end
                       else
                         nil
                       end
                     end),fn(x) -> is_nil(x) end)
          
          values = Enum.join(List.duplicate(["?"],Enum.count(Keyword.values(args))),",")
          keys = Keyword.keys(args)
          data = Exmapper.query("INSERT INTO #{__name__} (#{Enum.join(keys,",")}) VALUES (#{values})",Keyword.values(args),@repo)
          case data do
            {:ok_packet, _, _, id, _, _, _} ->
              data = get(id)
              run_callbacks(__MODULE__.__afters__, :create, data)
              {true, data}
            error ->
              Logger.info inspect error
              false
          end
        end
      end

      def update(args) when is_map(args) do update(to_keywords(args)) end
      def update(args) when is_list(args) do
        ret = run_callbacks(__MODULE__.__befores__, :update, get(args[:id]))
        if ret == false do
          false
        else
          id = args[:id]
          args = Keyword.delete(args,:id)
          args = Keyword.delete(Enum.map(args,fn({key,val}) ->
                                           if !Exmapper.is_virtual_type(__fields__[key][:type]) do
                                             Field.Transform.encode(__fields__[key][:type], key, val)
#                                             if __fields__[key][:type] == :datetime do
#                                               {key, {{val[:year],val[:month],val[:day]},{val[:hour],val[:minute],val[:second]}}}
#                                             else
#                                               {key,val}
#                                             end
                                           else
                                             nil 
                                           end
                                         end),nil)
          keys = Enum.join(Enum.map(args,fn({key,val}) -> "#{key} = ?" end),",")

          case Exmapper.query("UPDATE #{__name__} SET #{keys} WHERE id = ?",Keyword.values(args)++[id],@repo) do
            {:ok_packet, _, _, _, _, _, _} ->
              data = get(id)
              run_callbacks(__MODULE__.__afters__,:update, data)
              {true,data}
            error ->
              Logger.info inspect error
              false
          end
        end
      end

      # Fixme: use where builder from Exmapper
      def delete(args) when is_map(args) do delete(to_keywords(args)) end
      def delete(args) when is_list(args) do
        ret = run_callbacks(__MODULE__.__befores__, :delete, get(args[:id]))
        if ret == false do
          false
        else
          case Exmapper.query("DELETE FROM #{__name__} WHERE id = ?",[args[:id]],@repo) do
            {:ok_packet, _, _, _, _, _, _} ->
              run_callbacks(__MODULE__.__afters__, :delete, new(args))
              true
            error ->
              Logger.info inspect error
              false
          end
        end
      end
    end
  end

end
