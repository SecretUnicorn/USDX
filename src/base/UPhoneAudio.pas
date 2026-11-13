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
    Remote microphone through the hosted relay. A phone opens the relay's web
    page, types the room code this unit prints, and its microphone arrives here
    as PCM for player 1.

    The transport (TLS WebSocket to the relay, WebRTC data channel to the phone,
    PCM queue) lives in the native library built from native/phone-audio. Both
    that library and this unit come from UltraStar Community Edition
    (https://github.com/UltraStar-CE/USCE, GPL-2.0), reduced to the single slot
    the hosted relay serves and to the calls that slot needs.
*}

unit UPhoneAudio;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  SysUtils,
  Dynlibs;

type
  TPaCreate = function(Url, Ice: PAnsiChar): pointer; cdecl;
  TPaDestroy = procedure(Context: pointer); cdecl;
  TPaPoll = function(Context: pointer; Samples: pointer; Capacity: longint): longint; cdecl;
  TPaStatus = function(Context: pointer; Buffer: PAnsiChar; Capacity: longint): longint; cdecl;
  TPaSetClock = procedure(Context: pointer; HostTimeUs: int64); cdecl;
  TPaVersion = function: longint; cdecl;

  TPhoneAudio = class
    private
      FLibrary: TLibHandle;
      FContext: pointer;
      FError: string;
      FCreate: TPaCreate;
      FDestroy: TPaDestroy;
      FPoll: TPaPoll;
      FStatus: TPaStatus;
      FSetClock: TPaSetClock;
      FVersion: TPaVersion;
      function GetEnabled: boolean;
    public
      destructor Destroy; override;
      function Start(const Url: UTF8String; const LibraryPath: string = ''): boolean;
      procedure Stop;
      // Samples are 16 bit mono at 48 kHz. Returns how many were written.
      function Poll(Samples: pointer; Capacity: integer): integer;
      function Status: UTF8String;
      // What the phone has to type on the relay page, empty until registered.
      function RoomCode: UTF8String;
      function StateText: UTF8String;
      property Enabled: boolean read GetEnabled;
      property LastError: string read FError;
  end;

function PhoneAudio: TPhoneAudio;
function PhoneAudioLibraryName: string;
// The host a phone has to open, taken from the relay URL. Empty means the
// built-in relay.
function RelayHostName(const Url: UTF8String): UTF8String;

implementation

const
  DefaultRelayUrl = 'wss://usdx.at/ws/host';
  DefaultIceServer = 'stun:stun.l.google.com:19302';

var
  Instance: TPhoneAudio;

function PhoneAudio: TPhoneAudio;
begin
  if Instance = nil then
    Instance := TPhoneAudio.Create;
  Result := Instance;
end;

function PhoneAudioLibraryName: string;
begin
  {$IFDEF MSWINDOWS}
  Result := 'usce-phone-audio.dll';
  {$ELSE}
    {$IFDEF DARWIN}
    Result := 'libusce-phone-audio.dylib';
    {$ELSE}
    Result := 'libusce-phone-audio.so';
    {$ENDIF}
  {$ENDIF}
end;

function RelayHostName(const Url: UTF8String): UTF8String;
var
  Cut: integer;
begin
  Result := Trim(Url);
  if Result = '' then
    Result := DefaultRelayUrl;
  Cut := Pos('://', Result);
  if Cut > 0 then
    Result := Copy(Result, Cut + 3, MaxInt);
  Cut := Pos('/', Result);
  if Cut > 0 then
    Result := Copy(Result, 1, Cut - 1);
end;

{* Reads one string field out of the flat status object. Saves a JSON parser
   for two fields that the native library always writes as plain strings. *}
function StatusField(const Json, Name: UTF8String): UTF8String;
var
  Start, Stop: integer;
begin
  Result := '';
  Start := Pos('"' + Name + '":"', Json);
  if Start = 0 then
    Exit;
  Inc(Start, Length(Name) + 4);
  Stop := Start;
  while (Stop <= Length(Json)) and (Json[Stop] <> '"') do
    Inc(Stop);
  Result := Copy(Json, Start, Stop - Start);
end;

function TPhoneAudio.GetEnabled: boolean;
begin
  Result := FContext <> nil;
end;

function TPhoneAudio.Start(const Url: UTF8String; const LibraryPath: string): boolean;
var
  Path: string;
  RelayUrl: UTF8String;
begin
  Stop;
  FError := '';

  Path := LibraryPath;
  if Path = '' then
    Path := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0)))) +
      PhoneAudioLibraryName;

  FLibrary := LoadLibrary(Path);
  if FLibrary = NilHandle then
    FError := 'Cannot load the remote microphone transport: ' + Path
  else
  begin
    FVersion := TPaVersion(GetProcedureAddress(FLibrary, 'usce_pa_version'));
    FCreate := TPaCreate(GetProcedureAddress(FLibrary, 'usce_pa_create'));
    FDestroy := TPaDestroy(GetProcedureAddress(FLibrary, 'usce_pa_destroy'));
    FPoll := TPaPoll(GetProcedureAddress(FLibrary, 'usce_pa_poll'));
    FStatus := TPaStatus(GetProcedureAddress(FLibrary, 'usce_pa_status'));
    FSetClock := TPaSetClock(GetProcedureAddress(FLibrary, 'usce_pa_set_clock'));

    if not (Assigned(FVersion) and Assigned(FCreate) and Assigned(FDestroy) and
      Assigned(FPoll) and Assigned(FStatus) and Assigned(FSetClock)) then
      FError := 'The remote microphone transport is missing calls'
    else if FVersion() <> 1 then
      FError := 'The remote microphone transport speaks ABI ' +
        IntToStr(FVersion()) + ', not 1'
    else
    begin
      RelayUrl := Url;
      if RelayUrl = '' then
        RelayUrl := DefaultRelayUrl;
      FContext := FCreate(PAnsiChar(RelayUrl), PAnsiChar(UTF8String(DefaultIceServer)));
      if FContext = nil then
        FError := 'The relay connection could not be started';
    end;
  end;

  Result := FContext <> nil;
  if not Result then
    Stop;
end;

procedure TPhoneAudio.Stop;
begin
  if FContext <> nil then
    FDestroy(FContext);
  FContext := nil;
  if FLibrary <> NilHandle then
    UnloadLibrary(FLibrary);
  FLibrary := NilHandle;
end;

destructor TPhoneAudio.Destroy;
begin
  Stop;
  inherited;
end;

function TPhoneAudio.Poll(Samples: pointer; Capacity: integer): integer;
begin
  Result := 0;
  if not Enabled then
    Exit;
  // the library stamps the samples against the game's clock, not its own
  FSetClock(FContext, int64(GetTickCount64) * 1000);
  Result := FPoll(FContext, Samples, Capacity);
end;

function TPhoneAudio.Status: UTF8String;
var
  Buffer: array[0..2047] of AnsiChar;
begin
  Result := '';
  if Enabled and (FStatus(FContext, @Buffer[0], Length(Buffer)) >= 0) then
    Result := PAnsiChar(@Buffer[0]);
end;

function TPhoneAudio.RoomCode: UTF8String;
begin
  Result := StatusField(Status, 'code');
end;

function TPhoneAudio.StateText: UTF8String;
begin
  Result := StatusField(Status, 'state');
end;

finalization
  FreeAndNil(Instance);
end.
