-module(blog).
-export([main/1, run/1]).
-compile(export_all).

-define(conf(A,B), proplists:get_value(A,B)).
-define(conf(A,B,C), proplists:get_value(B, proplists:get_value(A,C))).

-record(conf, {index,
               index_tpl,
               index_out,
               rss_tpl,
               rss_out,
               rss_num=all,
               src,
               out,
               markdown=[],
               vars=[]
              }).

-record(article, {date,
                  title,
                  slug,
                  file,
                  text,
                  lg=en}).

run(BlogDir) ->
    io:format("Starting... "),
    statistics(wall_clock),
    main(BlogDir),
    {_, T} = statistics(wall_clock),
    io:format("Done in ~p ms~n",[T]),
    init:stop().

main(BlogDir) ->
    Conf = #conf{} = load_conf(BlogDir),
    recursive_copy(Conf#conf.src, Conf#conf.out),
    Index = get_entries(Conf),
    Entries = compile_files(Index, Conf#conf.vars, Conf#conf.markdown),
    save_entries(Conf#conf.out, Entries),
    create_index(Conf#conf.index_tpl, Conf#conf.index_out, Entries, Conf#conf.vars),
    rss(Conf#conf.rss_tpl, Conf#conf.rss_out, Conf#conf.rss_num, Entries, Conf#conf.vars).

load_conf(Base) ->
    AbsolutePath = filename:absname(Base),
    {ok, Conf} = file:consult(filename:join(AbsolutePath, "conf.cfg")),
    Src = filename:join(AbsolutePath, ?conf(sourcedir, Conf)),
    Out = filename:join(AbsolutePath, ?conf(outdir, Conf)),
    #conf{
      src = Src,
      out = Out,
      index = element(2, file:consult(filename:join(AbsolutePath,
                 ?conf(index, files, Conf)))),
      index_tpl = filename:join(Src, ?conf(index, tpl, Conf)),
      index_out = filename:join(Out, ?conf(index, out, Conf)),
      rss_tpl = filename:join(Src, ?conf(rss, tpl, Conf)),
      rss_out = filename:join(Out, ?conf(rss, out, Conf)),
      rss_num = ?conf(rss, num_entries, Conf),
      markdown = ?conf(markdown, Conf),
      vars = ?conf(vars, Conf)
    }.

recursive_copy(From, To) ->
    {ok, Files} = file:list_dir(From),
    {ok, Re} = re:compile("\\.(tpl|cfg|swp)$"), % skip useless files
    [ok = rec_copy(From, To, X) || X <- Files, nomatch =:= re:run(X, Re)],
    ok.

rec_copy(FromPath, ToPath, FileName) ->
    From = filename:join(FromPath, FileName),
    To = filename:join(ToPath, FileName),
    case filetype(From) of
        directory ->
            ok = filelib:ensure_dir(To),
            recursive_copy(From, To);
        file ->
            ok = filelib:ensure_dir(To),
            {ok, _} = file:copy(From, To),
            ok
    end.

get_entries(Conf=#conf{}) ->
     [#article{date=Date,
               title=Title,
               slug=sluggify(Title),
               file=filename:join(Conf#conf.src, File)} ||
        {Date, Title, File} <- Conf#conf.index].

compile_files([], _, _) -> [];
compile_files([A = #article{file=File} | Rest], Vars, Markdown) ->
    AllVars = [{meta, [{date, format_date(A#article.date)},
                       {title, A#article.title}]} | Vars],
    MarkdownRequired = fun(Re) ->
        case re:run(File, Re) of
            nomatch -> false;
            _ -> true
        end
    end,
    case lists:any(MarkdownRequired, Markdown) of
        true ->
            {ok, Bin} = file:read_file(File),
            MD = markdown(Bin),
            {ok, tpl} = erlydtl:compile(MD, tpl,
                         [{vars, AllVars}, {doc_root, filename:dirname(File)}]);
        false ->
            ok = erlydtl:compile(File, tpl, [{vars, AllVars}])
    end,
    {ok, Text} = tpl:render([]),
    [A#article{text=Text} | compile_files(Rest, Vars, Markdown)].

markdown(Bin) ->
    iolist_to_binary(parse(binary_to_list(Bin))).

% ideally we'd get a more clever algorithm but eh
parse([]) -> [];
parse("{% markdown %}" ++ Rest) ->
    {MD, Other} = markdown(Rest, []),
    [MD | parse(Other)];
parse([Char | Rest]) ->
    [Char | parse(Rest)].

markdown("{% endmarkdown %}" ++ Rest, Acc) ->
    {markdown:conv(lists:reverse(Acc)), Rest};
markdown([], _) ->
    error("Markdown closing tag ({% endmarkdown %}) not found");
markdown([Char|Rest], Acc) ->
    markdown(Rest, [Char|Acc]).

save_entries(_, []) -> ok;
save_entries(Path, [A = #article{} | Rest]) ->
    ok = file:write_file(filename:join(Path, A#article.slug++".html"),
                         A#article.text),
    save_entries(Path, Rest).

create_index(Src, Out, Pages, Vars) ->
    Index = [[{date, format_date(A#article.date)},
              {title, A#article.title},
              {slug, A#article.slug}] || A <- Pages],
    ok = erlydtl:compile(Src, tpl, [{vars, [{pages, lists:reverse(lists:sort(Index))}] ++ Vars}]),
    {ok, Text} = tpl:render([]),
    ok = file:write_file(Out, Text).

rss(Src, Out, Num, Index, Vars) ->
    Articles = lists:reverse(lists:sort(
               [[{sort, format_date(A#article.date)},
                 {date, A#article.date},
                 {title, A#article.title},
                 {slug, A#article.slug},
                 {desc,
                  "<![CDATA["++mochiweb_html:to_html({<<"div">>, 
                                        [],
                                        article(mochiweb_html:parse(T))})++"]]>"}] ||
                  A=#article{text=T} <- Index])),
    [[_,{date, LatestDate}|_]|_] = Articles,
    ok = erlydtl:compile(Src,
                         tpl,
                         [{vars, [{articles, lists:sublist((Articles), Num)},
                                  {latest_date, LatestDate}] ++ Vars}]),
    {ok, Text} = tpl:render([]),
    ok = file:write_file(Out, Text).

%% no need to be efficient, just make sense. worrying about French characters
%% only (and then some), mainly because I am French speaking.
sluggify(Str) ->
    Patterns = [{"[âäàáÀÄÂÁ]", "a"},
               {"[éêëèÉÊËÈ]", "e"},
               {"[ïîíìÏÎÌÍ]", "i"},
               {"[öôòóÖÔÒÓ]", "o"},
               {"[üûùúÜÛÙÚ]", "u"},
               {"[ÿýÝ]", "y"},
               {"[çÇ]", "c"},
               {"[^\\w\\d_-]", "-"},
               {"[-]{2,}", "-"},
               {"(?:^-)|(?:-$)", ""}],
    Slug = lists:foldl(fun({Pat, Rep}, Slug) ->
                       re:replace(Slug, Pat, Rep, [global, {return, binary}])
                       end,
                       Str,
                       Patterns),
    string:to_lower(binary_to_list(Slug)).

filetype(FileName) ->
    case filelib:is_dir(FileName) of
        true -> directory;
        false ->
            case filelib:is_file(FileName) of
                true -> file;
                false -> unknown  % symlinks?
            end
    end.

%% Use the mochiweb_html tree and find the article we need.
article({<<"article">>, _, Content}) -> Content;
article({_, _, Tree}) -> article(Tree);
article(Bin) when is_binary(Bin) -> not_found;
article([]) -> not_found;
article([H|T]) ->
    case article(H) of
        not_found -> article(T);
        Article -> Article
    end.

%% "Thu, 22 Jul 2010 00:00:00 EST" -> 2010 07 22
format_date(Str) ->
    {match, [Day,Month,Year]} = re:run(Str,
                                       "([\\d]{1,2}) ([\\w]{3}) ([\\d]{4})",
                                       [{capture, all_but_first, list}]),
    string:join([Year, month(Month), Day], " ").

month("Jan") -> "01";
month("Feb") -> "02";
month("Mar") -> "03";
month("Apr") -> "04";
month("May") -> "05";
month("Jun") -> "06";
month("Jul") -> "07";
month("Aug") -> "08";
month("Sep") -> "09";
month("Oct") -> "10";
month("Nov") -> "11";
month("Dec") -> "12".
