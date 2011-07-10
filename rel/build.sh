#!/usr/bin/env escript
%% -*- erlang -*-
%%! -smp enable -noshell
main(_) ->
    {ok, Conf} = file:consult("rel.conf"),
    {ok, Spec} = reltool:get_target_spec(Conf),
    reltool:eval_target_spec(Spec, code:root_dir(), "blogerl").
