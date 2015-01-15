defmodule Exmapper.Utils do

  def module_to_id(module) do
    String.to_atom((module |> Module.split |> List.last |> Exmapper.Utils.underscore) <> "_id")
  end

  def is_virtual_type(type), do: (Enum.find([:virtual, :belongs_to, :has_many, :setter],fn(x) -> x == type end) != nil) 

  def keys_to_atom(params) do
    Enum.map(params,fn({k,v}) ->
               if is_binary(k) do
                 {String.to_atom(k),v}
               else
                 {k,v}
               end
             end)
  end

  def to_map(value) do
    Enum.map(value, fn(x) ->
      Enum.reduce(x, %{},fn({k,v},acc) ->
        Map.put(acc,String.to_atom(k),v)
      end)
    end)
  end

  def to_keywords(value) do
    if value == nil do
      nil
    else
      if is_list(value) do
        Enum.map(value, fn(x) -> to_keywords(x) end)
      else
        value = Keyword.delete(Map.to_list(value), :__struct__)
        Enum.reject(Enum.map(value, fn({key,val}) ->
                               if is_map(val) do
                                 {key,to_keywords(val)}
                               else
                                 if is_function(val) do
                                   nil
                                 else
                                   {key,val}
                                 end
                               end
                             end),fn(x) -> is_nil(x) end)
      end
    end
  end

  defp _first_to_upper(<<s, t :: binary>>), do: <<to_upper_char(s)>> <> t
  defp _first_to_upper(<<>>), do: <<>>

  defp _first_to_lower(<<s, t :: binary>>), do: <<to_lower_char(s)>> <> t
  defp _first_to_lower(<<>>), do: <<>>

  defp to_upper_char(char) when char in ?a..?z, do: char - 32
  defp to_upper_char(char), do: char

  defp to_lower_char(char) when char in ?A..?Z, do: char + 32
  defp to_lower_char(char), do: char


   @doc """
  Converts the given atom or binary to underscore format.
  If an atom is given, it is assumed to be an Elixir module,
  so it is converted to a binary and then processed.
  ## Examples
      iex> Exmaper.Utils.underscore "FooBar"
      "foo_bar"
      iex> Exmapper.Utils.underscore "Foo.Bar"
      "foo/bar"
      iex> Exmapper.Utils.underscore Foo.Bar
      "foo/bar"
  In general, `underscore` can be thought of as the reverse of
  `camelize`, however, in some cases formatting may be lost:
      Exmapper.Utils.underscore "SAPExample"  #=> "sap_example"
      Exmapper.Utils.camelize   "sap_example" #=> "SapExample"
  """
  def underscore(atom) when is_atom(atom) do
    "Elixir." <> rest = Atom.to_string(atom)
    underscore(rest)
  end

  def underscore(""), do: ""

  def underscore(<<h, t :: binary>>) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<h, t, rest :: binary>>, _) when h in ?A..?Z and not t in ?A..?Z do
    <<?_, to_lower_char(h), t>> <> do_underscore(rest, t)
  end

  defp do_underscore(<<h, t :: binary>>, prev) when h in ?A..?Z and not prev in ?A..?Z do
    <<?_, to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<?-, t :: binary>>, _) do
    <<?_>> <> do_underscore(t, ?-)
  end

  defp do_underscore(<< "..", t :: binary>>, _) do
    <<"..">> <> underscore(t)
  end

  defp do_underscore(<<?.>>, _), do: <<?.>>

  defp do_underscore(<<?., t :: binary>>, _) do
    <<?/>> <> underscore(t)
  end

  defp do_underscore(<<h, t :: binary>>, _) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<>>, _) do
    <<>>
  end

  @doc """
  Converts the given string to CamelCase format.
  ## Examples
      iex> Exmapper.Utils.camelize "foo_bar"
      "FooBar"
  """
  def camelize(""), do: ""

  def camelize(<<?_, t :: binary>>) do
    camelize(t)
  end

  def camelize(<<h, t :: binary>>) do
    <<to_upper_char(h)>> <> do_camelize(t)
  end

  defp do_camelize(<<?_, ?_, t :: binary>>) do
    do_camelize(<< ?_, t :: binary >>)
  end

  defp do_camelize(<<?_, h, t :: binary>>) when h in ?a..?z do
    <<to_upper_char(h)>> <> do_camelize(t)
  end

  defp do_camelize(<<?_>>) do
    <<>>
  end

  defp do_camelize(<<?/, t :: binary>>) do
    <<?.>> <> camelize(t)
  end

  defp do_camelize(<<h, t :: binary>>) do
    <<h>> <> do_camelize(t)
  end

  defp do_camelize(<<>>) do
    <<>>
  end

end
