# borrowed from https://gist.github.com/Myuzu/7367461

defmodule Exmapper.Utils.SecureRandom do

  def hex(n) when is_integer(n) do
    random_bytes(n)
    |> Enum.map(fn (x) -> Integer.to_string(x, 16) end)
    |> Enum.join
    |> String.downcase
  end

  def random_bytes(n) when is_integer(n) do
    :erlang.binary_to_list(:crypto.strong_rand_bytes(n))
  end
end
