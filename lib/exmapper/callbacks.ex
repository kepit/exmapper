defmodule Exmapper.Callbacks do

  defmacro __using__(_opts) do
    quote do
      import Exmapper.Callbacks
      @before_compile Exmapper.Callbacks
      @exmapper_callbacks %{}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __exmapper_callbacks__, do: @exmapper_callbacks
    end
  end

  def register_callback(type, module, fun) when is_function(fun) or is_atom(fun) do
    quote bind_quoted: [type: type, callback: {module, fun}] do
      @exmapper_callbacks Map.update(@exmapper_callbacks, type, [callback], &[callback|&1])
    end
  end

  def register_callback(type, module, fun) do
    fun_name = String.to_atom("__exmapper_#{type}_callback_#{Exmapper.Utils.SecureRandom.hex(16)}__")
    ret = register_callback(type, module, fun_name)
    quote do
      def unquote(fun_name)(var!(data)) do
        unquote(fun[:do])
      end
      unquote(ret)
    end
  end

  defmacro before_create(mod, fun), do: register_callback(:before_create, mod, fun)
  defmacro before_delete(mod, fun), do: register_callback(:before_delete, mod, fun)
  defmacro before_update(mod, fun), do: register_callback(:before_update, mod, fun)
  defmacro after_create(mod, fun), do: register_callback(:after_create, mod, fun)
  defmacro after_delete(mod, fun), do: register_callback(:after_delete, mod, fun)
  defmacro after_update(mod, fun), do: register_callback(:after_update, mod, fun)

  defmacro before_create(fun), do: register_callback(:before_create, __CALLER__.module, fun)
  defmacro before_delete(fun), do: register_callback(:before_delete, __CALLER__.module, fun)
  defmacro before_update(fun), do: register_callback(:before_update, __CALLER__.module, fun)
  defmacro after_create(fun), do: register_callback(:after_create, __CALLER__.module, fun)
  defmacro after_delete(fun), do: register_callback(:after_delete, __CALLER__.module, fun)
  defmacro after_update(fun), do: register_callback(:after_update, __CALLER__.module, fun)

  def __apply__(callbacks, args) when is_nil(callbacks) do
    args
  end

  def __apply__(callbacks, args) do
    Enum.reduce Enum.reverse(callbacks), args, fn({mod, cb}, acc) ->
      case cb do
        callback when is_atom(callback) -> apply(mod, callback, [acc])
        callback -> callback.(acc)
      end
    end
  end


  def run_callbacks(module, callback, type, args) do
    callbacks = module.__exmapper_callbacks__[:"#{callback}_#{type}"]
    {:ok, __apply__(callbacks, args)}
  end

end

