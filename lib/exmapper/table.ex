defmodule Exmapper.Table do
  alias Exmapper.Field

  defmacro add_callback(type, cmd, fun) do
    if is_function(fun) or is_atom(fun) do
      quote do
        callbacks = Module.get_attribute(__MODULE__, unquote(type))
        Module.put_attribute(__MODULE__, unquote(type), Keyword.put(callbacks, :"#{unquote(cmd)}", callbacks[:"#{unquote(cmd)}"]++[unquote(fun)]))
      end
    else
      random = Exmapper.Utils.SecureRandom.hex(16)
      fun_name = String.to_atom("__exmapper_#{type}_callback_#{random}__")
      quote do
        def unquote(fun_name)(var!(data)) do
          unquote(fun[:do])
        end
        add_callback(unquote(type), unquote(cmd), unquote(fun_name)) 
      end
    end
  end
  
  defmacro before_create(fun), do: quote do: add_callback(:before_callbacks, :create, unquote(fun))
  defmacro before_delete(fun), do: quote do: add_callback(:before_callbacks, :delete, unquote(fun))
  defmacro before_update(fun), do: quote do: add_callback(:before_callbacks, :update, unquote(fun))
  defmacro after_create(fun), do: quote do: add_callback(:after_callbacks, :create, unquote(fun))
  defmacro after_delete(fun), do: quote do: add_callback(:after_callbacks, :delete, unquote(fun))
  defmacro after_update(fun), do: quote do: add_callback(:after_callbacks, :update, unquote(fun))

  defmacro schema(name,[do: block]) do

    if is_binary(name), do: name = String.to_atom(name)
    if is_list(name), do: name = List.to_atom(name)

    quote do
      import Exmapper.Field
      use Timex

      @fields []
      @before_callbacks [delete: [], create: [], update: []]
      @after_callbacks [delete: [], create: [], update: []]
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

      def __before_callbacks__, do: @before_callbacks
      def __after_callbacks__, do: @after_callbacks
      def __name__, do: @name
      def __fields__, do: @fields
    end
  end
end


