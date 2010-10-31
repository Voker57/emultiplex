-module(emultiplex).
-export([launch/0, launch/1]).

-define(TCP_OPTIONS,[binary, {packet, 0}, {active, true}, {reuseaddr, true}]).

launch() -> launch("emultiplex.conf").

launch(CfgLocation) ->
	Config = case file:consult(CfgLocation) of
		{ok, ConfigTerms} -> ConfigTerms;
		{error, Error} -> io:format("Couldn't read config: ~p, using default values~n", [Error]), []
	end,
	
	[AuthKey, CPort, LPort] = config:fetch_or_default_config([auth_key, client_port, server_port], Config, [{auth_key, "foobar"}, {client_port, 6789}, {server_port, 4567}]),
	
	erlang:display([AuthKey, CPort, LPort]),
		
	ets:new(clients, [public, named_table]),
	
	register(broadcaster, spawn_link(fun() ->	broadcaster() end)),
	
	register(authenticator, spawn_link(fun() -> authenticator(AuthKey) end)),
	
	{ok, CSocket} = gen_tcp:listen(CPort, ?TCP_OPTIONS),
	spawn_link(fun() -> client_greeter(CSocket) end),
	{ok, LSocket} = gen_tcp:listen(LPort, ?TCP_OPTIONS),
	spawn_link(fun() -> server_greeter(LSocket) end),
	
	
	receive
		{killme, pls} -> ok
	end.

server_greeter(Socket) ->
	case gen_tcp:accept(Socket) of
		{ok, SSocket} -> io:format("Server accepted, authenticating...~n"), 
		gen_tcp:controlling_process(SSocket, whereis(authenticator));
		A ->io:format("Error accepting server: ~p~n",[A])
	end,
	receive
		Msg -> io:format("Stray packet! ~p~n", [Msg])
	after 0 ->
		ok
	end,
	server_greeter(Socket).

client_greeter(Socket) ->
	case gen_tcp:accept(Socket) of
		{ok, CSocket} -> io:format("Client accepted~n"), ets:insert(clients, {CSocket});
		A ->io:format("Error accepting client: ~p~n",[A])
	end,
	client_greeter(Socket).

authenticator(AuthKey) ->
	receive
		{tcp, Sock, Data} ->
			AuthString = list_to_binary(AuthKey ++ "\n"),
			case Data of
				AuthString ->
					io:format("Server authenticated~n"), 
					gen_tcp:controlling_process(Sock, whereis(broadcaster));
				_ -> 
					io:format("Server not authenticated ~s~n"), 
					gen_tcp:close(Sock)
			end
	end,
	authenticator(AuthKey).

broadcaster() ->
	receive
		{tcp, _Sock, Data} ->
 			ets:foldl(fun({Victim}, _) ->
 				case gen_tcp:send(Victim, Data) of
 					ok -> foo;
 					{error, closed} -> "Client disconnected";
 					Error -> io:format("Client error: ~p~n",[Error]), ets:delete_object(clients, {Victim})
 				end
 				end, foo, clients)			
	end,
	broadcaster().