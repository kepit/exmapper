defmodule Exmapper.Adapters.Mysql do

  def connect(params) do
    user = params[:username]
    password = params[:password]
    database = params[:database]
    size = if is_nil(params[:pool_size]), do: 1, else: params[:pool_size]
    encoding = if is_nil(params[:encoding]), do: :utf8, else: params[:encoding]
    pool = if is_nil(params[:repo]), do: :default, else: params[:repo] 
    if is_binary(user), do: user = String.to_char_list(user)
    if is_binary(password), do: password = String.to_char_list(password)
    if is_binary(database), do: database = String.to_char_list(database)
    :application.start(:crypto)
    :application.start(:emysql)
    :emysql.add_pool(pool, [{:size,size}, {:user,user}, {:password,password}, {:database,database}, {:encoding,encoding}])
  end

  def query(pool, query, args) do
    :emysql.execute(pool, query, args)
  end

  def normalize_result({:result_packet,_,_,_,_} = ret) do
    {:ok, :emysql.as_proplist(ret)}
  end
  
  def normalize_result({:ok_packet, _seq_num, affected_rows, insert_id, status, warning_count, msg}) do
    {:ok, [insert_id: insert_id, affected_rows: affected_rows, status: status, msg: msg, warning_count: warning_count]}
  end

  def normalize_result({:error_packet, _seq_num, code, msg}) do
    {:error, [code: code, msg: msg]}
  end

  def normalize_result({:error_packet, _seq_num, _, code, msg}) do
    {:error, [code: code, msg: msg]}
  end


end
