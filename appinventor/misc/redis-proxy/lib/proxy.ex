defmodule Proxy do
  @moduledoc """
  Simple forward proxy which forwards SSL connections from Redis clients to a local instance.
  """

  @doc """
  Begins accepting SSL connections on the given `port`.
  Set certfile and keyfile based on machine this is deployed on.
  """
  def accept(port) do
    {:ok, socket} = :ssl.listen(port, [:binary, packet: :line, active: false, reuseaddr: true,
                                        certfile: "certificate.pem", keyfile: "key.pem", versions: []])
    loop_acceptor(socket)
  end

  # Accepts SSL client connection and opens tcp connection to Redis at localhost.
  # Handshakes, and spawns a process to read from the client and a process to write
  # to the client. Recurses to accept another client.
  defp loop_acceptor(socket) do
    # Client SSL accept/handshake
    {:ok, client} = :ssl.transport_accept(socket)
    :ok = :ssl.ssl_accept(client)

    # Redis TCP connection initiation
    {:ok, redis} = :gen_tcp.connect('127.0.0.1', 6379, [:binary, active: false])

    # Read/Write spawn and delegation
    {:ok, read_pid} = Task.Supervisor.start_child(Proxy.TaskSupervisor, fn -> read(redis, client) end)
    {:ok, write_pid} = Task.Supervisor.start_child(Proxy.TaskSupervisor, fn -> write(redis, client) end)
    :ok = :ssl.controlling_process(client, read_pid)
    :ok = :gen_tcp.controlling_process(redis, write_pid)

    # Recurse
    loop_acceptor(socket)
  end

  # Reads an SSL line from the client, writes it to Redis, and waits for another client line.
  defp read(redis, client) do
    client
    |> ssl_read_line()
    |> tcp_write_line(redis)

    read(redis, client)
  end

  # Reads a TCP line from Redis, writes it to the client, and waits for another Redis line.
  defp write(redis, client) do
    redis
    |> tcp_read_line()
    |> ssl_write_line(client)

    write(redis, client)
  end

  # Reads and returns a line from the given TCP socket.
  defp tcp_read_line(socket) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    data
  end

  # Writes the given line to the given TCP socket.
  defp tcp_write_line(line, socket) do
    :gen_tcp.send(socket, line)
  end

  # Reads and returns a line from the given SSL socket.
  defp ssl_read_line(socket) do
    {:ok, data} = :ssl.recv(socket, 0)
    data
  end

  # Writes the given line to the given SSL socket.
  defp ssl_write_line(line, socket) do
    :ssl.send(socket, line)
  end
end
