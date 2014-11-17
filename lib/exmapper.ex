defmodule Exmapper do
  require Logger

  def start(params), do: connect(params)
  def connect(params), do: Exmapper.Adapter.connect(params)
 
end
