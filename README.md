ExMapper
========

Elixir database wrapper

### Connect
```
Exmapper.connect(username: "[username]", password: "[password]", database: "[database]", pool_size: 1, encoding: :utf8)
```

### Model
```
defmodule Model do
	use Exmapper.Model
	table :models do
		field :name, :string

		before_to :delete, &Model.before_delete/1
		after_to :delete, &Model.after_delete/1
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
Model.to_keywords(Model.new) # Convert Map to keyword

Model.all
Model.all(id: 1)
Model.all("id.gte": 1) # Greater than 1
Model.all(limit: 2) # LIMIT 2
Model.all(order_by: "id DESC") # ORDER BY id DESC

Model.first()
Model.last()
Model.get([id])

Model.update(Model.first)
Model.create(Model.new)
Model.delete(Model.first)

```
