defmodule Message do
  defstruct [:prefix, :cmd, :params]

  def commands(:join), do: "JOIN"
  def commands(:mode), do: "MODE"
  def commands(:nick), do: "NICK"
  def commands(:notice), do: "NOTICE"
  def commands(:ping), do: "PING"
  def commands(:pong), do: "PONG"
  def commands(:privmsg), do: "PRIVMSG"
  def commands(:user), do: "USER"
  def replies(:rpl_endofmotd), do: "376"
  def replies(:err_nomotd), do: "422"

  def parse(raw) do
    tokens = raw |> String.trim() |> String.split(" ")
    prefix = if String.starts_with?(List.first(tokens), ":") do List.first(tokens) else nil end
    cmd = Enum.at(tokens, if prefix == nil do 0 else 1 end)
    ps = Enum.slice(tokens, if prefix == nil do 1 else 2 end..-1)
    i = Enum.find_index(ps, fn p -> String.starts_with?(p, ":") end)
    tl = if i == nil do nil else ps |> Enum.slice(i..-1) |> Enum.join(" ") end

    %Message{
      prefix: if prefix == nil do nil else String.slice(prefix, 1..-1) end,
      cmd: String.upcase(cmd), 
      params:
        case i do
          nil -> ps
          0 -> [tl]
          _ -> Enum.slice(ps, 0..i-1) ++ [tl]
        end
    }
  end

  def tostr(msg) do
    [
      if msg.prefix == nil do "" else ":#{msg.prefix}" end,
      msg.cmd,
      Enum.join(msg.params, " ")
    ]
    |> Enum.join(" ")
    |> String.trim()
  end

  def prep(msg) do
    String.to_charlist("#{tostr(msg)}\r\n")
  end

  def contents(msg) do
    case msg.params do
      [] -> ""
      ps  -> ps |> List.last() |> String.slice(1..-1)
    end
  end

  def origin(msg) do
    case msg.prefix do
      nil ->
        nil
      px ->
        if String.contains?(px, "!") do
          px |> String.split("!") |> List.first()
        else
          px
        end
    end
  end

  def join(chan, key \\ nil) do
    %Message{
      cmd: commands(:join),
      params: if key == nil do [chan] else [chan, key] end
    }
  end

  def mode(target, modes, param \\ nil) do
    %Message{
      cmd: commands(:mode),
      params: [target, modes] ++ if param == nil do [] else [":#{param}"] end
    }
  end

  def nick(n), do: %Message{cmd: commands(:nick), params: [n]}

  def pong(params), do: %Message{cmd: commands(:pong), params: params}

  def privmsg(recipient, contents) do
    %Message{cmd: commands(:privmsg), params: [recipient, ":#{contents}"]}
  end

  def user(name, realname) do
    %Message{
      cmd: commands(:user),
      params: [name, "0", "*", "#{if realname == nil do name else realname end}"]
    }
  end

  def registration(nck, usr \\ nil, realname \\ nil) do
    [nick(nck), user(if usr == nil do nck else usr end, realname)]
    |> Enum.map(fn m -> prep(m) end)
    |> List.flatten()
  end
end

defmodule Bot do
  defstruct [
    verbose: false,
    nick: "olimpia",
    user: "olimpia",
    chan: "#olimpia",
    chops: [],
    log: nil,
  ]

  @join Message.commands(:join)
  @mode Message.commands(:mode)
  @nick Message.commands(:nick)
  @notice Message.commands(:notice)
  @ping Message.commands(:ping)
  @pong Message.commands(:pong)
  @privmsg Message.commands(:privmsg)
  @user Message.commands(:user)
  @rpl_endofmotd Message.replies(:rpl_endofmotd)
  @err_nomotd Message.replies(:err_nomotd)

  def start(host, config) do
    sockopts = [:list, {:packet, :line}, {:active, false}]
    {:ok, sock} = :gen_tcp.connect(host, 6667, sockopts)
    :gen_tcp.send(sock, Message.registration(config.nick, config.user))
    log = case config.log do
      nil ->
        nil
      :stdio ->
        :stdio
      fname ->
        {:ok, device} = File.open(fname, [:write])
        device
    end
    listen(sock, config, log)
  end

  def listen(sock, config, log) do
    {:ok, data} = :gen_tcp.recv(sock, 0)
    m = data |> List.to_string() |> Message.parse()
    if config.verbose, do: IO.puts("< #{Message.tostr(m)}")
    if log != nil, do: IO.puts(log, "< #{Message.tostr(m)}")
    case handle(m, config) do
      nil -> :ok
      {:ok, res} ->
        if config.verbose, do: IO.puts("> #{Message.tostr(res)}")
        if log != nil, do: IO.puts(log, "> #{Message.tostr(res)}")
        :gen_tcp.send(sock, Message.prep(res))
    end
    listen(sock, config, log)
  end

  def handle(msg, config) do
    case msg.cmd do
      @ping -> {:ok, Message.pong(msg.params)}
      @rpl_endofmotd -> {:ok, Message.join(config.chan)}
      @err_nomotd -> {:ok, Message.join(config.chan)}
      @join ->
        if Message.origin(msg) in config.chops do
          {:ok, Message.mode(config.chan, "+o", Message.origin(msg))}
        end
      _ -> nil
    end
  end
end
