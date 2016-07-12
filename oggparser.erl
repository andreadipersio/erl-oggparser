-module(oggparser).

-export([parse_file/1,loop/0]).

-define(BUFSIZE, 1024).
-define(CAPTURE_PATTERN, "OggS").
-define(HEADER_SIZE, 32).

-type page_type() :: continued | bos | eos | regular.

-record(header, {version,
                 page_type :: page_type(),
                 abs_granule_pos,
                 stream_serial_no,
                 page_sequence_no,
                 page_checksum,
                 page_segments}).

parse_file(Filepath) ->
    case file:open(Filepath, [read, binary, raw]) of
        {error, Reason} ->
            exit(Reason);
        {ok, IoDevice} ->
            find_header(IoDevice)
    end.

find_header(IoDevice) ->
    Pid = spawn(oggparser, loop, []),
    find_header(IoDevice, 0, Pid).

find_header(IoDevice, Offset, PrinterPid) ->
    case file:pread(IoDevice, Offset, ?BUFSIZE) of
        {error, Reason} ->
            PrinterPid ! {self(), {error, Offset, Reason}};
        eof ->
            PrinterPid ! stop;
        {ok, Data} ->
            case is_capture_pattern(Data) of
                nomatch ->
                    find_header(IoDevice, Offset+?BUFSIZE, PrinterPid);
                {Start,_} ->
                    case file:pread(IoDevice, Offset+Start, ?HEADER_SIZE) of
                        {error, Reason} ->
                            PrinterPid ! {self(), {error, Start, Reason}};
                        {ok, HeaderBytes} ->
                            PrinterPid ! {self(), {new_page, Start, parse_header(HeaderBytes)}},
                            find_header(IoDevice, Offset+?HEADER_SIZE, PrinterPid)
                    end
            end
    end.

loop() ->
    receive
        {From, {new_page, At, Header}} ->
            io:format("@~p ~p~n", [At, Header]),
            loop();
        {From, {error, At, Msg}} ->
            io:format("@~p error --- ~p~n", [At, Msg]);
        stop ->
            true
    end.

is_capture_pattern(Bytes) ->
    binary:match(Bytes, <<?CAPTURE_PATTERN>>).

parse_header(Bytes) ->
    <<_                 : 4/binary,
      Version           : 8,
      PageType          : 8,
      AbsGranulePos     : 64,
      StreamSerialNo    : 32,
      PageNumber        : 32,
      Checksum          : 32,
      PageSegments      : 8,
      _/binary>> = Bytes,
    #header{version=Version,
            page_type=decode_page_type(PageType),
            abs_granule_pos=AbsGranulePos,
            stream_serial_no=StreamSerialNo,
            page_sequence_no=PageNumber,
            page_checksum=Checksum,
            page_segments=PageSegments}.

decode_page_type(PageType) ->
    case PageType of
        0 ->
            regular;
        1 ->
            continued;
        2 ->
            bos;
        4 ->
            eos
    end.

main(Filename) ->
    parse_file(Filename).
