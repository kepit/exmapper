defmodule Exmapper.Adapters.Mariaex.Worker do
  use GenServer


  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  def init(opts) do
    send(self(), {:connect, opts})
    Process.send_after(self(), :gc, 5000)
    {:ok, %{connection: nil}}
  end

  def query(pid, query, args) do
    GenServer.call(pid, {query, args})
  end

  def reconnect(opts) do
    Process.send_after(self(), {:connect, opts}, 1000)
  end

  def handle_info(:gc, state) do
    :erlang.garbage_collect(self())
    if state.connection != nil do
      :erlang.garbage_collect(state.connection)
    end
    Process.send_after(self(), :gc, 5000)
    {:noreply, state}
  end

  def handle_info({:connect, opts}, state) do
    Process.flag(:trap_exit, true)
    case Mariaex.Connection.start_link(opts) do
      {:ok, pid} ->
        {:noreply, %{state | connection: pid}}
      _ ->
        reconnect(opts)
        {:noreply, %{state | connection: nil}}
    end
  end
  
  def handle_call({query, args}, _from, state) do
    ret = case state.connection do
            nil ->
              {:error, "No connection to server"}
            pid ->
              Mariaex.Connection.query(pid, query, args)
          end
    {:reply, ret, state}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    {:stop, :normal, state}
  end
  
  def handle_info(data, state) do
    {:stop, :normal, state}
  end
  
end


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
                     worker_module: Exmapper.Adapters.Mariaex.Worker,
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
        Exmapper.Adapters.Mariaex.Worker.query(pid, query, args)
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
  def normalize_result({:error, reason}) do
    {:error, [code: "", msg: reason]}
  end

end
