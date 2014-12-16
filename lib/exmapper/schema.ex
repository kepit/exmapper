defmodule Exmapper.Schema do

  defmacro schema(name,[do: block]) do
    if is_binary(name), do: name = String.to_atom(name)
    if is_list(name), do: name = List.to_atom(name)
    quote do
      import Exmapper.Field
      
      @fields []
      @table_name unquote(name)

      field :id, :integer, primary_key: true, auto_increment: true, required: true

      unquote(block)
      
      defstruct Enum.map(@fields, fn({key,val}) -> {key,val[:opts][:default]} end)

      def __table_name__, do: @table_name
      def __fields__, do: @fields
    end
  end
end


