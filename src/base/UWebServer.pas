{* UltraStar Deluxe - Karaoke Game
 *
 * UltraStar Deluxe is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING. If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *}

{**
 * Small HTTP server that lets guests browse the song collection and queue
 * songs from their phone. It only serves one embedded page plus a handful of
 * JSON endpoints, there is no file access of any kind.
 *
 * Everything runs in its own thread and only talks to the game through
 * TWebQueue, which is guarded by a critical section.
 *}
unit UWebServer;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  SysUtils,
  Classes;

type
  TWebServerThread = class(TThread)
    private
      fPort:     integer; // port asked for, the bound one may be higher
      fBoundPort: integer;
      fListen:   longint;
      fStartErr: string;
      fStarted:  boolean;

      function  BindAndListen: boolean;
      procedure HandleClient(Sock: longint);
      function  ReadRequest(Sock: longint; out Method, Path, Body: RawByteString): boolean;
      procedure SendRaw(Sock: longint; const Data: RawByteString);
      procedure SendResponse(Sock: longint; const Status, ContentType: RawByteString;
                             const Body: RawByteString);
      procedure Route(Sock: longint; const Method, Path, Body: RawByteString);
    protected
      procedure Execute; override;
    public
      constructor Create(APort: integer);
      property Port: integer read fBoundPort;
      property StartError: string read fStartErr;
      property Started: boolean read fStarted;
  end;

  TWebServer = class
    private
      fThread:   TWebServerThread;
      fPort:     integer;
      fAddress:  string;
      fLastError: string;
    public
      constructor Create;
      destructor  Destroy; override;

      function  Start(APort: integer): boolean;
      procedure Stop;

      function  Running: boolean;
      property  Port: integer read fPort;
      { address guests have to open, e.g. http://192.168.1.20:8080 }
      property  Address: string read fAddress;
      { why the server is not running, empty if it is }
      property  LastError: string read fLastError;
  end;

var
  WebServer: TWebServer;

{* Address of the running server, empty string if it is not running. *}
function WebServerAddress: string;

{* Reason why the server is not running, empty string while it is. *}
function WebServerError: string;

implementation

uses
  Sockets,
  {$IFNDEF MSWINDOWS}
  BaseUnix,
  UnixType,
  {$ENDIF}
  StrUtils,
  UIni,
  ULog,
  UWebQueue;

const
  // a request that is not complete after this many bytes is dropped
  MaxRequestSize = 16 * 1024;
  MaxBodySize    = 8 * 1024;
  // clients that stop talking to us must not block the whole server
  ClientTimeoutMs = 5000;
  // if the configured port is taken, try a few of the following ones
  PortsToTry = 12;

{$IFDEF DARWIN}
const
  // <sys/socket.h>, not exported by every FPC version
  USDX_SO_NOSIGPIPE = $1022;
{$ENDIF}

{$IF Defined(UNIX) and not Defined(DARWIN)}
const
  // <sys/socket.h>, keeps send() from raising SIGPIPE
  USDX_MSG_NOSIGNAL = $4000;
{$IFEND}

{$IFDEF MSWINDOWS}
const
  // winsock2.h
  USDX_SO_RCVTIMEO = $1006;
  USDX_SO_SNDTIMEO = $1005;
{$ENDIF}

var
  CachedPage: RawByteString = '';

{$I UWebQueuePage.inc}

{ small helpers }

function JsonEscape(const S: UTF8String): RawByteString;
var
  I: integer;
  C: char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"':  Result := Result + '\"';
      '\':  Result := Result + '\\';
      #8:   Result := Result + '\b';
      #9:   Result := Result + '\t';
      #10:  Result := Result + '\n';
      #12:  Result := Result + '\f';
      #13:  Result := Result + '\r';
      else
        if (C < #32) then
          Result := Result + '\u00' + LowerCase(IntToHex(Ord(C), 2))
        else
          Result := Result + C;
    end;
  end;
end;

function UrlDecode(const S: RawByteString): RawByteString;
var
  I, Len: integer;
  Code: integer;
begin
  Result := '';
  I := 1;
  Len := Length(S);
  while (I <= Len) do
  begin
    if (S[I] = '+') then
      Result := Result + ' '
    else if (S[I] = '%') and (I + 2 <= Len) and
            TryStrToInt('$' + Copy(S, I + 1, 2), Code) then
    begin
      Result := Result + Chr(Code);
      Inc(I, 2);
    end
    else
      Result := Result + S[I];
    Inc(I);
  end;
end;

{**
 * Reads a single parameter out of a query string or an urlencoded body.
 *}
function GetParam(const Query, Name: RawByteString): RawByteString;
var
  Params: TStringList;
  I, P: integer;
  Key: RawByteString;
begin
  Result := '';

  Params := TStringList.Create;
  try
    Params.Delimiter := '&';
    Params.StrictDelimiter := true;
    Params.DelimitedText := Query;

    for I := 0 to Params.Count - 1 do
    begin
      P := Pos('=', Params[I]);
      if (P <= 0) then
        Continue;

      Key := Copy(Params[I], 1, P - 1);
      if (UrlDecode(Key) = Name) then
      begin
        Result := UrlDecode(Copy(Params[I], P + 1, Length(Params[I]) - P));
        Exit;
      end;
    end;
  finally
    Params.Free;
  end;
end;

function ParamToInt(const Query, Name: RawByteString; Default: integer): integer;
begin
  Result := StrToIntDef(GetParam(Query, Name), Default);
end;

{* Ids sent by a client can be anything, 0 stands for "no match". *}
function ParamToID(const Query, Name: RawByteString): cardinal;
var
  Value: int64;
begin
  Value := StrToInt64Def(GetParam(Query, Name), 0);
  if (Value < 0) or (Value > High(cardinal)) then
    Value := 0;

  Result := cardinal(Value);
end;

function WebServerAddress: string;
begin
  if Assigned(WebServer) and WebServer.Running then
    Result := WebServer.Address
  else
    Result := '';
end;

function WebServerError: string;
begin
  if (not Assigned(WebServer)) then
    Result := 'not started'
  else
    Result := WebServer.LastError;
end;

{**
 * IP address this machine is reachable at in the local network. Asking a
 * connectionless UDP socket which interface it would use avoids having to
 * enumerate interfaces, no packet is sent.
 *}
function DetectLocalAddress: string;
var
  Sock: longint;
  Addr, Local: TInetSockAddr;
  Len: longint;
begin
  Result := '127.0.0.1';

  Sock := fpSocket(AF_INET, SOCK_DGRAM, 0);
  if (Sock < 0) then
    Exit;

  try
    FillChar(Addr, SizeOf(Addr), 0);
    Addr.sin_family := AF_INET;
    Addr.sin_port := htons(53);
    Addr.sin_addr := StrToNetAddr('8.8.8.8');

    if (fpConnect(Sock, @Addr, SizeOf(Addr)) <> 0) then
      Exit;

    Len := SizeOf(Local);
    FillChar(Local, SizeOf(Local), 0);
    if (fpGetSockName(Sock, @Local, @Len) <> 0) then
      Exit;

    if (Local.sin_addr.s_addr <> 0) then
      Result := NetAddrToStr(Local.sin_addr);
  finally
    CloseSocket(Sock);
  end;
end;

{**
 * Builds the address the guests have to open. [WebQueue] Address in the config
 * overrides the detected one, which is what machines with several host names
 * or network interfaces need. It takes a host name, a host:port or a complete
 * URL.
 *}
function BuildDisplayAddress(Port: integer): string;
var
  Custom: string;
begin
  Custom := Trim(Ini.WebQueueAddress);

  if (Custom = '') then
  begin
    Result := Format('http://%s:%d', [DetectLocalAddress, Port]);
    Exit;
  end;

  // a complete URL is taken as it is
  if (Pos('://', Custom) > 0) then
  begin
    Result := Custom;
    Exit;
  end;

  // host without a port gets the port the server actually listens on
  if (Pos(':', Custom) > 0) then
    Result := 'http://' + Custom
  else
    Result := Format('http://%s:%d', [Custom, Port]);
end;

{ TWebServerThread }

constructor TWebServerThread.Create(APort: integer);
begin
  fPort      := APort;
  fBoundPort := APort;
  fListen    := -1;
  fStartErr  := '';
  fStarted   := false;

  inherited Create(false);
end;

{**
 * Binds the configured port. Other programs on the machine may hold it, so a
 * few of the following ports are tried as well instead of leaving the feature
 * silently switched off. The port that worked is reported back through
 * fBoundPort and ends up in the address shown in-game.
 *}
function TWebServerThread.BindAndListen: boolean;
var
  Addr: TInetSockAddr;
  One:  longint;
  Port: integer;
begin
  Result := false;

  for Port := fPort to fPort + PortsToTry - 1 do
  begin
    if (Port > 65535) then
      Break;

    fListen := fpSocket(AF_INET, SOCK_STREAM, 0);
    if (fListen < 0) then
    begin
      fStartErr := 'could not create socket';
      Exit;
    end;

    One := 1;
    fpSetSockOpt(fListen, SOL_SOCKET, SO_REUSEADDR, @One, SizeOf(One));

    FillChar(Addr, SizeOf(Addr), 0);
    Addr.sin_family      := AF_INET;
    Addr.sin_port        := htons(word(Port));
    Addr.sin_addr.s_addr := 0; // INADDR_ANY, guests connect over the network

    if (fpBind(fListen, @Addr, SizeOf(Addr)) = 0) and
       (fpListen(fListen, 16) = 0) then
    begin
      fBoundPort := Port;
      if (Port <> fPort) then
        Log.LogWarn(Format('Port %d is in use, listening on %d instead', [fPort, Port]),
                    'UWebServer');
      fStartErr := '';
      Result := true;
      Exit;
    end;

    CloseSocket(fListen);
    fListen := -1;
  end;

  fStartErr := Format('ports %d to %d are all in use', [fPort, fPort + PortsToTry - 1]);
end;

procedure TWebServerThread.Execute;
var
  Client: longint;
{$IFDEF MSWINDOWS}
  TimeoutMs: longint;
{$ELSE}
  TV: TTimeVal;
  {$IFDEF DARWIN}
  One: longint;
  {$ENDIF}
{$ENDIF}
begin
  if not BindAndListen then
  begin
    fStarted := true; // unblocks Start(), StartError tells what went wrong
    Exit;
  end;

  fStarted := true;

  while not Terminated do
  begin
    Client := fpAccept(fListen, nil, nil);

    if Terminated then
    begin
      if (Client >= 0) then
        CloseSocket(Client);
      Break;
    end;

    if (Client < 0) then
    begin
      // transient error, do not spin at full speed
      Sleep(50);
      Continue;
    end;

    {$IFDEF MSWINDOWS}
      TimeoutMs := ClientTimeoutMs;
      fpSetSockOpt(Client, SOL_SOCKET, USDX_SO_RCVTIMEO, @TimeoutMs, SizeOf(TimeoutMs));
      fpSetSockOpt(Client, SOL_SOCKET, USDX_SO_SNDTIMEO, @TimeoutMs, SizeOf(TimeoutMs));
    {$ELSE}
      TV.tv_sec  := ClientTimeoutMs div 1000;
      TV.tv_usec := 0;
      fpSetSockOpt(Client, SOL_SOCKET, SO_RCVTIMEO, @TV, SizeOf(TV));
      fpSetSockOpt(Client, SOL_SOCKET, SO_SNDTIMEO, @TV, SizeOf(TV));
      {$IFDEF DARWIN}
        One := 1;
        // writing to a socket the phone already closed must not kill the game
        fpSetSockOpt(Client, SOL_SOCKET, USDX_SO_NOSIGPIPE, @One, SizeOf(One));
      {$ENDIF}
    {$ENDIF}

    try
      HandleClient(Client);
    except
      on E: Exception do
        Log.LogError('Request failed: ' + E.Message, 'UWebServer');
    end;

    CloseSocket(Client);
  end;

  if (fListen >= 0) then
  begin
    CloseSocket(fListen);
    fListen := -1;
  end;
end;

procedure TWebServerThread.SendRaw(Sock: longint; const Data: RawByteString);
var
  Sent, Res, Total: longint;
  Flags: longint;
begin
  Total := Length(Data);
  Sent  := 0;

  Flags := 0;
  {$IF Defined(UNIX) and not Defined(DARWIN)}
    Flags := USDX_MSG_NOSIGNAL;
  {$IFEND}

  while (Sent < Total) do
  begin
    Res := fpSend(Sock, @Data[Sent + 1], Total - Sent, Flags);
    if (Res <= 0) then
      Exit; // client is gone, nothing we can do about it
    Inc(Sent, Res);
  end;
end;

procedure TWebServerThread.SendResponse(Sock: longint; const Status, ContentType: RawByteString;
                                        const Body: RawByteString);
var
  Header: RawByteString;
begin
  Header := 'HTTP/1.1 ' + Status + #13#10 +
            'Content-Type: ' + ContentType + #13#10 +
            'Content-Length: ' + IntToStr(Length(Body)) + #13#10 +
            'Cache-Control: no-store' + #13#10 +
            'Connection: close' + #13#10#13#10;

  SendRaw(Sock, Header + Body);
end;

function TWebServerThread.ReadRequest(Sock: longint; out Method, Path, Body: RawByteString): boolean;
var
  Buffer:  RawByteString;
  Chunk:   array[0..2047] of AnsiChar;
  Res:     longint;
  HeadEnd: integer;
  Line:    RawByteString;
  Headers: RawByteString;
  P, ContentLength: integer;
  LenPos:  integer;
begin
  Result  := false;
  Method  := '';
  Path    := '';
  Body    := '';
  Buffer  := '';
  HeadEnd := 0;

  // read until the header is complete
  while (HeadEnd = 0) do
  begin
    Res := fpRecv(Sock, @Chunk[0], SizeOf(Chunk), 0);
    if (Res <= 0) then
      Exit;

    SetLength(Buffer, Length(Buffer) + Res);
    System.Move(Chunk[0], Buffer[Length(Buffer) - Res + 1], Res);

    HeadEnd := Pos(#13#10#13#10, Buffer);
    if (HeadEnd = 0) and (Length(Buffer) > MaxRequestSize) then
      Exit;
  end;

  Headers := Copy(Buffer, 1, HeadEnd - 1);
  Body    := Copy(Buffer, HeadEnd + 4, Length(Buffer) - HeadEnd - 3);

  // request line
  P := Pos(#13#10, Headers);
  if (P > 0) then
    Line := Copy(Headers, 1, P - 1)
  else
    Line := Headers;

  P := Pos(' ', Line);
  if (P <= 0) then
    Exit;

  Method := UpperCase(Copy(Line, 1, P - 1));
  Line   := Copy(Line, P + 1, Length(Line) - P);

  P := Pos(' ', Line);
  if (P > 0) then
    Path := Copy(Line, 1, P - 1)
  else
    Path := Line;

  // body, if the client announced one
  ContentLength := 0;
  LenPos := Pos('content-length:', LowerCase(Headers));
  if (LenPos > 0) then
  begin
    Line := Copy(Headers, LenPos + 15, 20);
    P := Pos(#13#10, Line);
    if (P > 0) then
      Line := Copy(Line, 1, P - 1);
    ContentLength := StrToIntDef(Trim(Line), 0);
  end;

  if (ContentLength > MaxBodySize) then
    Exit;

  while (Length(Body) < ContentLength) do
  begin
    Res := fpRecv(Sock, @Chunk[0], SizeOf(Chunk), 0);
    if (Res <= 0) then
      Break;

    SetLength(Body, Length(Body) + Res);
    System.Move(Chunk[0], Body[Length(Body) - Res + 1], Res);
  end;

  Result := (Method <> '') and (Path <> '');
end;

procedure TWebServerThread.HandleClient(Sock: longint);
var
  Method, Path, Body: RawByteString;
begin
  if not ReadRequest(Sock, Method, Path, Body) then
    Exit;

  Route(Sock, Method, Path, Body);
end;

function SongsToJson(const Songs: TWebSongArray; Total, Offset: integer): RawByteString;
var
  I: integer;
begin
  Result := '{"total":' + IntToStr(Total) + ',"offset":' + IntToStr(Offset) + ',"songs":[';

  for I := 0 to High(Songs) do
  begin
    if (I > 0) then
      Result := Result + ',';

    Result := Result +
      '{"id":' + IntToStr(Songs[I].ID) +
      ',"artist":"' + JsonEscape(Songs[I].Artist) +
      '","title":"' + JsonEscape(Songs[I].Title) +
      '","language":"' + JsonEscape(Songs[I].Language) +
      '","genre":"' + JsonEscape(Songs[I].Genre) +
      '","year":' + IntToStr(Songs[I].Year) +
      ',"duet":' + IfThen(Songs[I].IsDuet, 'true', 'false') + '}';
  end;

  Result := Result + ']}';
end;

function QueueToJson: RawByteString;
var
  Entries: TWebQueueEntryArray;
  I: integer;
begin
  Entries := WebQueue.GetEntries;

  Result := '{"rev":' + IntToStr(WebQueue.Revision) + ',"entries":[';

  for I := 0 to High(Entries) do
  begin
    if (I > 0) then
      Result := Result + ',';

    Result := Result +
      '{"entry":' + IntToStr(Entries[I].EntryID) +
      ',"artist":"' + JsonEscape(Entries[I].Artist) +
      '","title":"' + JsonEscape(Entries[I].Title) +
      '","singer":"' + JsonEscape(Entries[I].Singer) + '"}';
  end;

  Result := Result + ']}';
end;

procedure TWebServerThread.Route(Sock: longint; const Method, Path, Body: RawByteString);
var
  Target, Query: RawByteString;
  P: integer;
  Songs: TWebSongArray;
  Total, Offset, Limit: integer;
begin
  Target := Path;
  Query  := '';

  P := Pos('?', Target);
  if (P > 0) then
  begin
    Query  := Copy(Target, P + 1, Length(Target) - P);
    Target := Copy(Target, 1, P - 1);
  end;

  if (Method <> 'GET') and (Method <> 'POST') then
  begin
    SendResponse(Sock, '405 Method Not Allowed', 'text/plain; charset=utf-8', 'method not allowed');
    Exit;
  end;

  // the song request page
  if (Method = 'GET') and ((Target = '/') or (Target = '/index.html')) then
  begin
    if (CachedPage = '') then
      CachedPage := BuildWebQueuePage;
    SendResponse(Sock, '200 OK', 'text/html; charset=utf-8', CachedPage);
    Exit;
  end;

  if (Method = 'GET') and (Target = '/api/songs') then
  begin
    Offset := ParamToInt(Query, 'offset', 0);
    Limit  := ParamToInt(Query, 'limit', 60);
    if (Limit > 500) then
      Limit := 500;

    Songs := WebQueue.SearchSongs(GetParam(Query, 'q'), Offset, Limit, Total);
    SendResponse(Sock, '200 OK', 'application/json; charset=utf-8',
                 SongsToJson(Songs, Total, Offset));
    Exit;
  end;

  if (Method = 'GET') and (Target = '/api/queue') then
  begin
    SendResponse(Sock, '200 OK', 'application/json; charset=utf-8', QueueToJson);
    Exit;
  end;

  if (Method = 'GET') and (Target = '/api/status') then
  begin
    SendResponse(Sock, '200 OK', 'application/json; charset=utf-8',
      '{"songs":' + IntToStr(WebQueue.SongCount) +
      ',"ready":' + IfThen(WebQueue.IndexReady, 'true', 'false') +
      ',"queue":' + IntToStr(WebQueue.Count) +
      ',"rev":' + IntToStr(WebQueue.Revision) + '}');
    Exit;
  end;

  if (Method = 'POST') and (Target = '/api/queue/add') then
  begin
    if WebQueue.Enqueue(ParamToID(Body, 'id'),
                        GetParam(Body, 'singer')) then
      SendResponse(Sock, '200 OK', 'application/json; charset=utf-8', '{"ok":true}')
    else
      SendResponse(Sock, '200 OK', 'application/json; charset=utf-8',
                   '{"ok":false,"error":"Song is not available or the queue is full"}');
    Exit;
  end;

  if (Method = 'POST') and (Target = '/api/queue/remove') then
  begin
    SendResponse(Sock, '200 OK', 'application/json; charset=utf-8',
      '{"ok":' + IfThen(WebQueue.RemoveEntry(ParamToID(Body, 'entry')),
                        'true', 'false') + '}');
    Exit;
  end;

  if (Method = 'POST') and (Target = '/api/queue/move') then
  begin
    SendResponse(Sock, '200 OK', 'application/json; charset=utf-8',
      '{"ok":' + IfThen(WebQueue.MoveEntry(ParamToID(Body, 'entry'),
                                           StrToIntDef(GetParam(Body, 'offset'), 0)),
                        'true', 'false') + '}');
    Exit;
  end;

  SendResponse(Sock, '404 Not Found', 'text/plain; charset=utf-8', 'not found');
end;

{ TWebServer }

constructor TWebServer.Create;
begin
  inherited Create;

  fThread    := nil;
  fPort      := 0;
  fAddress   := '';
  fLastError := 'not started';
end;

destructor TWebServer.Destroy;
begin
  Stop;

  inherited;
end;

function TWebServer.Running: boolean;
begin
  Result := Assigned(fThread) and (fThread.StartError = '');
end;

function TWebServer.Start(APort: integer): boolean;
var
  Waited: integer;
begin
  Result := false;

  if Assigned(fThread) then
    Exit;

  if (APort <= 0) or (APort > 65535) then
  begin
    fLastError := Format('invalid port %d', [APort]);
    Log.LogError('Web queue server not started: ' + fLastError, 'UWebServer');
    Exit;
  end;

  fPort := APort;
  fThread := TWebServerThread.Create(APort);

  // wait for the socket to be bound so we can report failures right away
  Waited := 0;
  while (not fThread.Started) and (Waited < 2000) do
  begin
    Sleep(10);
    Inc(Waited, 10);
  end;

  if (fThread.StartError <> '') then
  begin
    fLastError := fThread.StartError;
    Log.LogError('Web queue server could not start: ' + fLastError, 'UWebServer');
    Stop;
    Exit;
  end;

  fLastError := '';
  fPort := fThread.Port;
  fAddress := BuildDisplayAddress(fPort);
  Log.LogStatus(Format('Web queue server listening on port %d, address shown in-game: %s',
                       [fPort, fAddress]), 'UWebServer');

  Result := true;
end;

procedure TWebServer.Stop;
var
  Sock: longint;
  Addr: TInetSockAddr;
begin
  if not Assigned(fThread) then
    Exit;

  fThread.Terminate;

  // the thread is blocked in accept(), a connection from here wakes it up
  Sock := fpSocket(AF_INET, SOCK_STREAM, 0);
  if (Sock >= 0) then
  begin
    FillChar(Addr, SizeOf(Addr), 0);
    Addr.sin_family := AF_INET;
    Addr.sin_port   := htons(word(fPort));
    Addr.sin_addr   := StrToNetAddr('127.0.0.1');

    fpConnect(Sock, @Addr, SizeOf(Addr));
    CloseSocket(Sock);
  end;

  fThread.WaitFor;
  FreeAndNil(fThread);

  fAddress := '';
end;

end.
