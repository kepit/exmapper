ExMapper
========

Elixir MySQL database library

### Connect
```
Exmapper.connect(username: "username", password: "password", database: "database", repo: :repository_name, pool_size: 1, encoding: :utf8)
```

### Model
```
defmodule Model do
  use Exmapper.Model, repo: :repository
  schema :models do
    field :name, :string

    has_many :other_models, OtherModel, through: ModelOtherModel, foreign_key: :key_id

    before_delete, :before_delete

    before_create do
      data
    end

  end
  

  def before_delete(data) do
    Logger.warn inspect data
  end

  def after_delete(data) do
    Logger.warn inspect data
  end
end
```

### Queries
```
Model.migrate # Migrate table
Model.upgrade # Upgrade table
Model.drop # Drop table

Model.all 
Model.all(id: 1)
Model.all("id.gte": 1) # Greater than 1
Model.all(limit: 2) # LIMIT 2
Model.all(order_by: "id DESC") # ORDER BY id DESC

Model.first().assoc.([:all, name: "test"])
Model.first().assoc.([:first, name: "test"])
Model.first().assoc.([:create, name: "test"])

Model.first()
Model.last()
Model.get([id])

Model.update(Model.first)
Model.create(Model.new)
Model.delete(Model.first)

```
