%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2009-2010. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%

-module(reltool).

%% Public
-export([
         main/1, % Escript
         start/0, start/1, start_link/1, debug/0, % GUI
         start_server/1, get_server/1, stop/1,
         get_config/1, get_config/3, get_rel/2, get_script/2,
         create_target/2, get_target_spec/1, eval_target_spec/3,
         install/2
        ]).

-include("reltool.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Main function for escript
-spec main([escript_arg()]) -> ok.
main(_) ->
    process_flag(trap_exit, true),
    {ok, WinPid} = start_link([]),
    receive
        {'EXIT', WinPid, shutdown} ->
            ok;
        {'EXIT', WinPid, normal} ->
            ok;
        {'EXIT', WinPid, Reason} ->
            io:format("EXIT: ~p\n", [Reason]),
            erlang:halt(1)
    end.

%% Start main window process
-spec start() -> {ok, window_pid()}.
start() ->
    start([]).

%% Start main window process
-spec start(options()) -> {ok, window_pid() | {error, reason()}}.
start(Options)when is_list(Options)  ->
    {ok, WinPid} = start_link(Options),
    unlink(WinPid),
    {ok, WinPid}.

%% Start main window process with wx debugging enabled
-spec debug() -> {ok, window_pid()}.
debug() ->
    {ok, WinPid} = start_link([{wx_debug, 2}]),
    unlink(WinPid),
    {ok, WinPid}.

%% Start main window process with options
-spec start_link(options()) -> {ok, window_pid() | {error, reason()}}.
start_link(Options) when is_list(Options) ->
    case reltool_sys_win:start_link(Options) of
        {ok, WinPid} ->
            {ok, WinPid};
        {error, Reason} ->
            {error, lists:flatten(io_lib:format("~p", [Reason]))}
    end.

%% Start server process with options
-spec start_server(options()) -> {ok, server_pid()} | {error, reason()}.
start_server(Options) ->
    case reltool_server:start_link(Options) of
        {ok, ServerPid, _Common, _Sys} ->
            {ok, ServerPid};
        {error, Reason} ->
            {error, lists:flatten(io_lib:format("~p", [Reason]))}
    end.

%% Start server process with options
-spec get_server(window_pid()) -> {ok, server_pid()} | {error, reason()}.
get_server(WinPid) ->
    case reltool_sys_win:get_server(WinPid) of
        {ok, ServerPid} ->
            {ok, ServerPid};
        {error, Reason} ->
            {error, lists:flatten(io_lib:format("~p", [Reason]))}
    end.

%% Stop a server or window process
-spec stop(server_pid() | window_pid()) -> ok | {error, reason()}.
stop(Pid) when is_pid(Pid) ->
    Ref = erlang:monitor(process, Pid),
    unlink(Pid),
    exit(Pid, shutdown),
    receive
        {'DOWN', Ref, _, _, shutdown} ->
            ok;
        {'DOWN', Ref, _, _, Reason} ->
            {error, lists:flatten(io_lib:format("~p", [Reason]))}
    end.

%% Internal library function
-spec eval_server(server(), fun((server_pid()) -> term())) ->
 {ok, server_pid()} | {error, reason()}.
eval_server(Pid, Fun) when is_pid(Pid) ->
    Fun(Pid);
eval_server(Options, Fun) when is_list(Options), is_function(Fun, 1) ->
    case start_server(Options) of
        {ok, Pid} ->
            Res = Fun(Pid),
            stop(Pid),
            Res;
        {error, Reason} ->
            {error, Reason}
    end.

%% Get reltool configuration
-spec get_config(server()) -> {ok, config()} | {error, reason()}.
get_config(PidOrOption) ->
    get_config(PidOrOption, false, false).

-spec get_config(server(), incl_defaults(), incl_derived()) ->
			{ok, config()} | {error, reason()}.
get_config(PidOrOptions, InclDef, InclDeriv)
  when is_pid(PidOrOptions); is_list(PidOrOptions) ->
    eval_server(PidOrOptions,
		fun(Pid) ->
			reltool_server:get_config(Pid, InclDef, InclDeriv)
		end).

%% Get contents of release file
-spec get_rel(server(), rel_name()) -> {ok, rel_file()} | {error, reason()}.
get_rel(PidOrOptions, RelName)
  when is_pid(PidOrOptions); is_list(PidOrOptions) ->
    eval_server(PidOrOptions,
		fun(Pid) -> reltool_server:get_rel(Pid, RelName) end).

%% Get contents of boot script file
-spec get_script(server(), rel_name()) ->
			{ok, script_file()} | {error, reason()}.
get_script(PidOrOptions, RelName)
  when is_pid(PidOrOptions); is_list(PidOrOptions) ->
   eval_server(PidOrOptions,
	       fun(Pid) -> reltool_server:get_script(Pid, RelName) end).

%% Generate a target system
-spec create_target(server(), target_dir()) -> ok | {error, reason()}.
create_target(PidOrOptions, TargetDir)
  when is_pid(PidOrOptions); is_list(PidOrOptions) ->
    eval_server(PidOrOptions,
		fun(Pid) -> reltool_server:gen_target(Pid, TargetDir) end).

%% Generate a target system
-spec get_target_spec(server()) -> {ok, target_spec()} | {error, reason()}.
get_target_spec(PidOrOptions)
  when is_pid(PidOrOptions); is_list(PidOrOptions) ->
    eval_server(PidOrOptions, fun(Pid) -> reltool_server:gen_spec(Pid) end).

%% Generate a target system
-spec eval_target_spec(target_spec(), root_dir(), target_dir()) ->
			      ok | {error, reason()}.
eval_target_spec(Spec, SourceDir, TargetDir)
  when is_list(SourceDir), is_list(TargetDir) ->
    reltool_target:eval_spec(Spec, SourceDir, TargetDir).

%% Install a target system
-spec install(rel_name(), dir()) -> ok | {error, reason()}.
install(RelName, TargetDir) ->
    reltool_target:install(RelName, TargetDir).