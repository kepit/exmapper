defmodule ExmapperTest do
  use ExUnit.Case

  test "the truth" do
    assert 1 + 1 == 2
  end
end

defmodule TestData do
  use Exmapper.Model, repo: :exmapper_test
  schema "test_data" do
    field :strindata, :string
    field :jsondata, :json
    field :integerdata, :integer
    field :booleandata, :boolean
    field :datatimedata, :datetime
  end
end
