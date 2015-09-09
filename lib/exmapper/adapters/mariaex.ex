defmodule Exmapper.Adapters.Mariaex do
  
  
  def connect(params) do
    user = params[:username]
    password = params[:password]
    database = params[:database]
    size = if is_nil(params[:pool_size]), do: 10, else: params[:pool_size]
    encoding = if is_nil(params[:encoding]), do: :utf8, else: params[:encoding]
    pool = if is_nil(params[:repo]), do: :default, else: params[:repo] 
    pool_options = [
                     name: {:local, pool},
                     worker_module: Mariaex.Connection,
                     size: size,
                     max_overflow: 10
                 ]
    children = [:poolboy.child_spec(:mariaex, pool_options, [username: user, password: password, database: database, charset: to_string(encoding)])]
    Supervisor.start_link(children, strategy: :one_for_one)
    :ok
  end

  def query(pool, query, args) do
    :poolboy.transaction(
      pool,
      fn(pid) ->
        Mariaex.Connection.query(pid, query, args)
      end)
  end

  
  def normalize_result({:ok, %Mariaex.Result{command: cmd, rows: rows} = result}) when rows != nil do
    ret = Enum.map(result.rows, fn(row) ->
                  Enum.map_reduce(result.columns, 0, fn(col, num) ->
                                    {{col, Enum.at(row, num)}, num + 1}
                                  end) |> elem(0)
                end)
     {:ok, ret}
  end

  def normalize_result({:ok, %Mariaex.Result{command: cmd} = result}) do
    {:ok, [insert_id: result.last_insert_id, affected_rows: result.num_rows, status: nil, msg: nil, warning_count: 0]}
  end

  
  
  def normalize_result({:error, %Mariaex.Error{mariadb: %{code: code, message: message}}}) do
    {:error, [code: code, msg: message]}
  end
  def normalize_result({:error, %Mariaex.Error{message: msg}}) do
    {:error, [code: "", msg: msg]}
  end

end
