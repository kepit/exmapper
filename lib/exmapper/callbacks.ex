defmodule Exmapper.Callbacks do

  defmacro __using__(_opts) do
    quote do
      import Exmapper.Callbacks
      @before_compile Exmapper.Callbacks
      @before_callbacks [delete: [], create: [], update: []]
      @after_callbacks [delete: [], create: [], update: []]
    end
  end

  defmacro __before_compile__(env) do
    before_callbacks = Module.get_attribute env.module, :before_callbacks
    after_callbacks = Module.get_attribute env.module, :after_callbacks
    quote do
      def __before_callbacks__, do: unquote(before_callbacks)
      def __after_callbacks__, do: unquote(after_callbacks)
    end
  end

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

  def run_callbacks(module, callbacks, type, args) do
    ret = Enum.reduce callbacks[type], args, fn(cb, acc) ->
      case cb do
        callback when is_atom(callback) -> apply(module, callback, [acc])
        callback -> callback.(acc)
      end
    end
    {:ok, ret}
  end

end

