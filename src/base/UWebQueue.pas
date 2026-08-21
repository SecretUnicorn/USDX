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
 * Song request queue that is filled by the local web server (see UWebServer).
 *
 * The queue itself is shared between the web server thread and the main
 * thread, therefore every access goes through a critical section. The web
 * server thread must never touch the song objects of USongs directly, it only
 * works on the song index built by RebuildSongIndex.
 *}
unit UWebQueue;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  SysUtils,
  Classes;

type
  {* A single song as it is offered on the web page. *}
  TWebSong = record
    ID:         cardinal;   // stable id, derived from the song file path
    Artist:     UTF8String;
    Title:      UTF8String;
    Language:   UTF8String;
    Genre:      UTF8String;
    Edition:    UTF8String;
    Year:       integer;
    IsDuet:     boolean;
    Path:       UTF8String; // full path of the txt file, used to find the song again
    SearchText: UTF8String; // lower case ASCII, used for the web search
  end;
  TWebSongArray = array of TWebSong;

  {* A song that has been requested through the web page. *}
  TWebQueueEntry = record
    EntryID: cardinal;      // unique for the runtime of the game
    SongID:  cardinal;
    Artist:  UTF8String;
    Title:   UTF8String;
    Singer:  UTF8String;    // optional name entered on the web page
    Path:    UTF8String;
  end;
  TWebQueueEntryArray = array of TWebQueueEntry;

  TWebQueue = class
    private
      Lock:        TRTLCriticalSection;
      SongIndex:   TWebSongArray;
      Entries:     TWebQueueEntryArray;
      NextEntryID: cardinal;
      fRevision:   cardinal; // bumped on every change so the web page can poll cheaply
      fIndexReady: boolean;

      // both expect the lock to be held by the caller
      function FindEntryIndex(EntryID: cardinal): integer;
      function FindSongIndex(SongID: cardinal): integer;
    public
      constructor Create;
      destructor  Destroy; override;

      {* Rebuilds the song snapshot the web server works on. Called by
         TCatSongs.Refresh, i.e. whenever the song list changed. *}
      procedure RebuildSongIndex;

      // the following methods are safe to call from the web server thread
      function  SearchSongs(const Search: UTF8String; Offset, Limit: integer;
                            out Total: integer): TWebSongArray;
      function  SongCount: integer;
      function  IndexReady: boolean;
      function  Enqueue(SongID: cardinal; const Singer: UTF8String): boolean;
      function  RemoveEntry(EntryID: cardinal): boolean;
      function  MoveEntry(EntryID: cardinal; Offset: integer): boolean;
      procedure Clear;
      function  GetEntries: TWebQueueEntryArray;
      function  Count: integer;
      function  Revision: cardinal;

      // main thread only
      function  TakeNext(out Entry: TWebQueueEntry): boolean;
      procedure RequestStartNext;
  end;

var
  WebQueue: TWebQueue;

{* Stable id of a song, derived from its file path (FNV-1a). *}
function WebQueueSongID(const Path: UTF8String): cardinal;

{* True if the web queue feature is switched on in the config. *}
function WebQueueEnabled: boolean;

{* Called once per frame from UMain.CheckEvents. Starts the next queued song
   as soon as the game is in a state where that is possible. *}
procedure ProcessWebQueueRequest;

{* Draws the queue overlay. Called from TDisplay.Draw. *}
procedure DrawWebQueueOverlay;

procedure ToggleWebQueueOverlay;
function  WebQueueOverlayVisible: boolean;

{* Shows/hides the big QR code of the song request address. *}
procedure ToggleWebQueueQRCode;
function  WebQueueQRCodeVisible: boolean;
procedure HideWebQueueQRCode;

implementation

uses
  Math,
  UDisplay,
  UGraphic,
  UIni,
  ULanguage,
  ULog,
  UParty,
  UPath,
  UPlaylist,
  UQRCode,
  URenderer,
  UScreenName,
  UScreenSong,
  USong,
  USongs,
  UText,
  UWebServer;

const
  // number of queue entries shown in the in-game overlay
  OverlayMaxEntries = 5;
  // upper bound for the queue, keeps a misbehaving client from filling memory
  WebQueueMaxLength = 100;

var
  // main thread only
  OverlayOverride: integer = -1; // -1: follow the config, 0: hidden, 1: shown
  StartRequested:  boolean = false;
  CachedRevision:  cardinal = 0;
  CachedEntries:   TWebQueueEntryArray;
  CacheValid:      boolean = false;

  QRVisible:       boolean = false;
  QRCode:          TQRCode;
  QRAddress:       string = ''; // address the cached code was built from

function WebQueueSongID(const Path: UTF8String): cardinal;
var
  I: integer;
begin
  // FNV-1a, gives us a short id that stays the same as long as the song file
  // does, no matter how the song list is sorted at the moment. The hash
  // relies on wrap-around, so range and overflow checks are off here.
  {$PUSH}
  {$R-}
  {$Q-}
  Result := 2166136261;
  for I := 1 to Length(Path) do
  begin
    Result := Result xor cardinal(Ord(Path[I]));
    Result := Result * 16777619;
  end;
  {$POP}

  // 0 is used as "no song" further down
  if (Result = 0) then
    Result := 1;
end;

function WebQueueEnabled: boolean;
begin
  Result := (Ini.WebQueue = 1);
end;

function WebQueueOverlayVisible: boolean;
begin
  if (OverlayOverride < 0) then
    Result := (Ini.WebQueueOverlay = 1)
  else
    Result := (OverlayOverride = 1);
end;

procedure ToggleWebQueueOverlay;
begin
  if WebQueueOverlayVisible then
    OverlayOverride := 0
  else
    OverlayOverride := 1;
end;

procedure ToggleWebQueueQRCode;
begin
  QRVisible := not QRVisible;
end;

function WebQueueQRCodeVisible: boolean;
begin
  Result := QRVisible;
end;

procedure HideWebQueueQRCode;
begin
  QRVisible := false;
end;

{ TWebQueue }

constructor TWebQueue.Create;
begin
  inherited Create;

  InitCriticalSection(Lock);
  SetLength(SongIndex, 0);
  SetLength(Entries, 0);
  NextEntryID := 1;
  fRevision   := 1;
  fIndexReady := false;
end;

destructor TWebQueue.Destroy;
begin
  SetLength(SongIndex, 0);
  SetLength(Entries, 0);
  DoneCriticalSection(Lock);

  inherited;
end;

function TWebQueue.FindEntryIndex(EntryID: cardinal): integer;
var
  I: integer;
begin
  Result := -1;
  for I := 0 to High(Entries) do
    if (Entries[I].EntryID = EntryID) then
    begin
      Result := I;
      Exit;
    end;
end;

function TWebQueue.FindSongIndex(SongID: cardinal): integer;
var
  I: integer;
begin
  Result := -1;
  for I := 0 to High(SongIndex) do
    if (SongIndex[I].ID = SongID) then
    begin
      Result := I;
      Exit;
    end;
end;

procedure TWebQueue.RebuildSongIndex;
var
  I, Count: integer;
  CurSong:  TSong;
  NewIndex: TWebSongArray;
  FullPath: UTF8String;
begin
  if (not Assigned(Songs)) or (not Assigned(Songs.SongList)) then
    Exit;

  // build the snapshot outside of the lock, it may take a moment on big
  // collections and the web server should not have to wait for it
  SetLength(NewIndex, Songs.SongList.Count);
  Count := 0;

  for I := 0 to Songs.SongList.Count - 1 do
  begin
    CurSong := TSong(Songs.SongList[I]);
    if (CurSong = nil) or CurSong.Main then
      Continue;
    if (CurSong.Path = nil) or (CurSong.FileName = nil) then
      Continue;

    FullPath := CurSong.Path.Append(CurSong.FileName).ToUTF8();

    NewIndex[Count].ID         := WebQueueSongID(FullPath);
    NewIndex[Count].Artist     := CurSong.Artist;
    NewIndex[Count].Title      := CurSong.Title;
    NewIndex[Count].Language   := CurSong.Language;
    NewIndex[Count].Genre      := CurSong.Genre;
    NewIndex[Count].Edition    := CurSong.Edition;
    NewIndex[Count].Year       := CurSong.Year;
    NewIndex[Count].IsDuet     := CurSong.isDuet;
    NewIndex[Count].Path       := FullPath;
    NewIndex[Count].SearchText := CurSong.ArtistASCII + ' ' + CurSong.TitleASCII + ' ' +
                                  CurSong.LanguageASCII + ' ' + CurSong.EditionASCII + ' ' +
                                  CurSong.GenreASCII + ' ' + IntToStr(CurSong.Year);
    Inc(Count);
  end;

  SetLength(NewIndex, Count);

  EnterCriticalSection(Lock);
  try
    SongIndex   := NewIndex;
    fIndexReady := true;
    Inc(fRevision);
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function TWebQueue.SearchSongs(const Search: UTF8String; Offset, Limit: integer;
                               out Total: integer): TWebSongArray;
var
  I, Added:  integer;
  Matches:   array of integer;
  MatchCnt:  integer;
  Needle:    UTF8String;
  Words:     TStringList;
  W:         integer;
  Matched:   boolean;
begin
  SetLength(Result, 0);
  Total := 0;

  Needle := Trim(LowerCase(Search));

  Words := TStringList.Create;
  EnterCriticalSection(Lock);
  try
    if (Needle <> '') then
    begin
      Words.Delimiter := ' ';
      Words.StrictDelimiter := true;
      Words.DelimitedText := Needle;
    end;

    SetLength(Matches, Length(SongIndex));
    MatchCnt := 0;

    for I := 0 to High(SongIndex) do
    begin
      Matched := true;
      for W := 0 to Words.Count - 1 do
        if (Words[W] <> '') and (Pos(Words[W], SongIndex[I].SearchText) = 0) then
        begin
          Matched := false;
          Break;
        end;

      if Matched then
      begin
        Matches[MatchCnt] := I;
        Inc(MatchCnt);
      end;
    end;

    Total := MatchCnt;

    if (Offset < 0) then
      Offset := 0;
    if (Limit <= 0) then
      Limit := MatchCnt;

    Added := 0;
    SetLength(Result, Max(0, Min(Limit, MatchCnt - Offset)));
    I := Offset;
    while (I < MatchCnt) and (Added < Length(Result)) do
    begin
      Result[Added] := SongIndex[Matches[I]];
      Inc(Added);
      Inc(I);
    end;
  finally
    LeaveCriticalSection(Lock);
    Words.Free;
  end;
end;

function TWebQueue.SongCount: integer;
begin
  EnterCriticalSection(Lock);
  try
    Result := Length(SongIndex);
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function TWebQueue.IndexReady: boolean;
begin
  EnterCriticalSection(Lock);
  try
    Result := fIndexReady;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function TWebQueue.Enqueue(SongID: cardinal; const Singer: UTF8String): boolean;
var
  SongIdx, Len: integer;
begin
  Result := false;

  EnterCriticalSection(Lock);
  try
    SongIdx := FindSongIndex(SongID);
    if (SongIdx < 0) then
      Exit;

    if (Length(Entries) >= WebQueueMaxLength) then
      Exit;

    Len := Length(Entries);
    SetLength(Entries, Len + 1);

    Entries[Len].EntryID := NextEntryID;
    Entries[Len].SongID  := SongID;
    Entries[Len].Artist  := SongIndex[SongIdx].Artist;
    Entries[Len].Title   := SongIndex[SongIdx].Title;
    Entries[Len].Path    := SongIndex[SongIdx].Path;
    Entries[Len].Singer  := Copy(Singer, 1, 40);

    Inc(NextEntryID);
    Inc(fRevision);

    Result := true;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function TWebQueue.RemoveEntry(EntryID: cardinal): boolean;
var
  I, Idx: integer;
begin
  Result := false;

  EnterCriticalSection(Lock);
  try
    Idx := FindEntryIndex(EntryID);
    if (Idx < 0) then
      Exit;

    for I := Idx to High(Entries) - 1 do
      Entries[I] := Entries[I + 1];
    SetLength(Entries, Length(Entries) - 1);

    Inc(fRevision);
    Result := true;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function TWebQueue.MoveEntry(EntryID: cardinal; Offset: integer): boolean;
var
  Idx, NewIdx: integer;
  Tmp: TWebQueueEntry;
begin
  Result := false;

  EnterCriticalSection(Lock);
  try
    Idx := FindEntryIndex(EntryID);
    if (Idx < 0) then
      Exit;

    NewIdx := Idx + Offset;
    if (NewIdx < 0) or (NewIdx > High(Entries)) or (NewIdx = Idx) then
      Exit;

    Tmp := Entries[Idx];
    Entries[Idx] := Entries[NewIdx];
    Entries[NewIdx] := Tmp;

    Inc(fRevision);
    Result := true;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

procedure TWebQueue.Clear;
begin
  EnterCriticalSection(Lock);
  try
    if (Length(Entries) = 0) then
      Exit;

    SetLength(Entries, 0);
    Inc(fRevision);
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function TWebQueue.GetEntries: TWebQueueEntryArray;
var
  I: integer;
begin
  EnterCriticalSection(Lock);
  try
    SetLength(Result, Length(Entries));
    for I := 0 to High(Entries) do
      Result[I] := Entries[I];
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function TWebQueue.Count: integer;
begin
  EnterCriticalSection(Lock);
  try
    Result := Length(Entries);
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function TWebQueue.Revision: cardinal;
begin
  EnterCriticalSection(Lock);
  try
    Result := fRevision;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function TWebQueue.TakeNext(out Entry: TWebQueueEntry): boolean;
var
  I: integer;
begin
  Result := false;

  EnterCriticalSection(Lock);
  try
    if (Length(Entries) = 0) then
      Exit;

    Entry := Entries[0];
    for I := 0 to High(Entries) - 1 do
      Entries[I] := Entries[I + 1];
    SetLength(Entries, Length(Entries) - 1);

    Inc(fRevision);
    Result := true;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

procedure TWebQueue.RequestStartNext;
begin
  StartRequested := true;
end;

{ starting the next queued song }

{**
 * Looks up a queued song in the current CatSongs array. The path is the
 * identity of a song, the array position changes with the sorting.
 *}
function FindCatSongIndex(const Entry: TWebQueueEntry): integer;
var
  I: integer;
  CurSong: TSong;
begin
  Result := -1;

  for I := 0 to High(CatSongs.Song) do
  begin
    CurSong := CatSongs.Song[I];
    if (CurSong = nil) or CurSong.Main then
      Continue;
    if (CurSong.Path = nil) or (CurSong.FileName = nil) then
      Continue;

    if (CurSong.Path.Append(CurSong.FileName).ToUTF8() = Entry.Path) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

{**
 * Leaves search results and playlist view so that every song of the
 * collection can be selected again. May rebuild CatSongs.Song, so song
 * indices have to be looked up after this call.
 *}
procedure ResetSongView;
begin
  CatSongs.SetFilter('', fltAll);
  PlaylistMan.UnsetPlaylist;
  ScreenSong.HideCatTL;
end;

{**
 * Opens the category the given song lives in, otherwise the song stays
 * invisible while the category list is shown.
 *}
procedure OpenCategoryOf(CatIndex: integer);
var
  I: integer;
begin
  if (Ini.Tabs <> 1) then
    Exit;

  for I := CatIndex downto 0 do
    if CatSongs.Song[I].Main then
    begin
      ScreenSong.ShowCatTL(I);
      CatSongs.ShowCategory(CatSongs.Song[I].OrderNum);
      Break;
    end;
end;

{**
 * Pops entries off the queue until one of them could be started.
 *}
function StartNextQueuedSong: boolean;
var
  Entry:    TWebQueueEntry;
  CatIndex: integer;
begin
  Result := false;

  while WebQueue.TakeNext(Entry) do
  begin
    ResetSongView;

    CatIndex := FindCatSongIndex(Entry);
    if (CatIndex < 0) then
    begin
      // song vanished (renamed/deleted since it was queued), skip it
      Log.LogWarn('Queued song not found any more: ' + Entry.Artist + ' - ' + Entry.Title,
                  'UWebQueue.StartNextQueuedSong');
      Continue;
    end;

    OpenCategoryOf(CatIndex);

    ScreenSong.Mode := smNormal;
    ScreenSong.MakeMedley := false;

    if (TSongMenuMode(Ini.SongMenu) in [smRoulette, smChessboard, smList]) then
      ScreenSong.SkipTo(CatSongs.VisibleIndex(CatIndex), CatIndex, CatSongs.VisibleSongs)
    else
    begin
      ScreenSong.Interaction := CatIndex;
      ScreenSong.FixSelected;
    end;

    ScreenSong.SetScrollRefresh;
    ScreenSong.StartSong;
    QRVisible := false;

    Log.LogStatus('Starting queued song: ' + Entry.Artist + ' - ' + Entry.Title,
                  'UWebQueue.StartNextQueuedSong');

    Result := true;
    Exit;
  end;
end;

procedure ProcessWebQueueRequest;
begin
  if (not StartRequested) then
    Exit;

  if (not Assigned(WebQueue)) or (not Assigned(Display)) or (not Assigned(ScreenSong)) then
  begin
    StartRequested := false;
    Exit;
  end;

  // nothing left to start
  if (WebQueue.Count = 0) then
  begin
    StartRequested := false;
    Exit;
  end;

  // wait until the running screen change is done
  if Assigned(Display.NextScreen) then
    Exit;

  // leaving the editor would throw away unsaved work
  if (Display.CurrentScreen = @ScreenEditSub) or
     (Display.CurrentScreen = @ScreenEditConvert) or
     (Display.CurrentScreen = @ScreenEdit) then
  begin
    StartRequested := false;
    Log.LogInfo('Song request ignored while the editor is open', 'UWebQueue.ProcessWebQueueRequest');
    Exit;
  end;

  // a running party game has its own song selection, do not interfere
  if Party.bPartyGame then
  begin
    StartRequested := false;
    Log.LogWarn('Song request ignored, a party game is running', 'UWebQueue.ProcessWebQueueRequest');
    Exit;
  end;

  // The sing and score screens are built by the player name screen and need
  // the avatars and colours it prepares. Send the host there once, the next
  // request then starts the song right away.
  if (not Assigned(ScreenSing)) or (not Assigned(ScreenScore)) then
  begin
    StartRequested := false;
    Log.LogInfo('Player setup needed before the first requested song can start',
                'UWebQueue.ProcessWebQueueRequest');
    if (Display.CurrentScreen <> @ScreenName) then
    begin
      ScreenName.Goto_SingScreen := false;
      Display.FadeTo(@ScreenName);
    end;
    Exit;
  end;

  if (Display.CurrentScreen = @ScreenSong) then
  begin
    StartRequested := false;
    StartNextQueuedSong;
  end
  else if (Display.CurrentScreen = @ScreenSing) then
  begin
    // end the running song without going to the score screen, the request
    // is handled once we are back on the song screen
    ScreenSing.FadeOut := true;
    ScreenSing.Finish;
    Display.FadeTo(@ScreenSong);
  end
  else
  begin
    Display.FadeTo(@ScreenSong);
  end;
end;

{ overlay }

function TruncateToWidth(const Text: UTF8String; MaxWidth: real): UTF8String;
var
  Len: integer;
begin
  Result := Text;
  if (TextWidth(Result) <= MaxWidth) then
    Exit;

  Len := Length(Result);
  while (Len > 1) and (TextWidth(Copy(Result, 1, Len) + '...') > MaxWidth) do
  begin
    Dec(Len);
    // do not cut a UTF-8 sequence in half
    while (Len > 1) and (Ord(Result[Len + 1]) and $C0 = $80) do
      Dec(Len);
  end;

  Result := Copy(Result, 1, Len) + '...';
end;

{* The queue panel in the lower left corner. *}
procedure DrawQueuePanel;
var
  I, Shown:  integer;
  PanelX, PanelY, PanelW, PanelH: real;
  LineY:     real;
  Line:      UTF8String;
  Header:    UTF8String;
  Total:     integer;
  Revision:  cardinal;
const
  LineHeight = 15;
  TitleHeight = 19;
  // leave the button bar at the bottom of most screens uncovered
  BottomMargin = 38;
begin
  Revision := WebQueue.Revision;
  if (not CacheValid) or (Revision <> CachedRevision) then
  begin
    CachedEntries  := WebQueue.GetEntries;
    CachedRevision := Revision;
    CacheValid     := true;
  end;

  Total := Length(CachedEntries);
  Shown := Min(Total, OverlayMaxEntries);

  PanelW := 320;
  PanelH := TitleHeight + LineHeight * Max(Shown, 1) + 11;
  if (Total > Shown) then
    PanelH := PanelH + LineHeight;

  PanelX := 5;
  PanelY := 600 - PanelH - BottomMargin;

  Renderer.DepthTest := false;
  Renderer.DrawQuad(PanelX, PanelY, 0, PanelW, PanelH, 0, 0, 0, 0.6);

  SetFontFamily(0);
  SetFontStyle(ftRegular);
  SetFontItalic(false);
  SetFontReflection(false, 0);

  // headline: song count and the address the guests have to open
  Header := Format('%s (%d) - ', [Language.Translate('WEBQUEUE_TITLE'), Total]);
  if (WebServerAddress <> '') then
    Header := Header + WebServerAddress
  else
    Header := Header + Language.Translate('WEBQUEUE_OFFLINE') + ' (' + WebServerError + ')';

  SetFontSize(15);
  SetFontColor(1, 0.82, 0.2, 1);
  SetFontPos(PanelX + 6, PanelY + 2);
  PrintText(TruncateToWidth(Header, PanelW - 12));

  SetFontSize(14);
  LineY := PanelY + TitleHeight;

  if (Total = 0) then
  begin
    SetFontColor(0.75, 0.75, 0.75, 1);
    SetFontPos(PanelX + 6, LineY);
    PrintText(TruncateToWidth(Language.Translate('WEBQUEUE_EMPTY'), PanelW - 12));
  end
  else
  begin
    for I := 0 to Shown - 1 do
    begin
      if (I = 0) then
        SetFontColor(1, 1, 1, 1)
      else
        SetFontColor(0.75, 0.75, 0.75, 1);

      Line := IntToStr(I + 1) + '. ' + CachedEntries[I].Artist + ' - ' + CachedEntries[I].Title;
      if (CachedEntries[I].Singer <> '') then
        Line := Line + ' [' + CachedEntries[I].Singer + ']';

      SetFontPos(PanelX + 6, LineY);
      PrintText(TruncateToWidth(Line, PanelW - 12));
      LineY := LineY + LineHeight;
    end;

    if (Total > Shown) then
    begin
      SetFontColor(0.6, 0.6, 0.6, 1);
      SetFontPos(PanelX + 6, LineY);
      PrintText(Format(Language.Translate('WEBQUEUE_MORE'), [Total - Shown]));
    end;
  end;

  Renderer.DepthTest := true;
end;

{**
 * Big QR code of the request address, so guests can just point their phone at
 * the screen instead of typing an address.
 *}
procedure DrawQRPanel;
var
  Scale, Modules, X, Y: integer;
  Size, OriginX, OriginY: real;
  Address, Line: UTF8String;
const
  QuietZone = 4;   // light margin a QR code needs around it, in modules
  MaxPixels = 380;
begin
  Address := WebServerAddress;

  Renderer.DepthTest := false;
  Renderer.DrawQuad(0, 0, 0, 800, 600, 0, 0, 0, 0.8);

  SetFontFamily(0);
  SetFontStyle(ftRegular);
  SetFontItalic(false);
  SetFontReflection(false, 0);

  if (Address <> '') and (QRAddress <> Address) then
  begin
    if QREncode(Address, QRCode) then
      QRAddress := Address
    else
    begin
      QRCode.Size := 0;
      QRAddress := '';
      Log.LogWarn('Address does not fit into a QR code: ' + Address, 'UWebQueue.DrawQRPanel');
    end;
  end;

  if (Address = '') or (QRCode.Size = 0) then
  begin
    SetFontSize(24);
    SetFontColor(1, 0.6, 0.4, 1);
    Line := Language.Translate('WEBQUEUE_OFFLINE');
    if (Address = '') then
      Line := Line + ' (' + WebServerError + ')';
    SetFontPos((800 - TextWidth(Line)) / 2, 280);
    PrintText(Line);
    Renderer.DepthTest := true;
    Exit;
  end;

  Modules := QRCode.Size + 2 * QuietZone;
  Scale   := Trunc(MaxPixels / Modules);
  if (Scale < 1) then
    Scale := 1;

  Size    := Scale * Modules;
  OriginX := (800 - Size) / 2;
  OriginY := 78;

  // headline
  SetFontSize(30);
  SetFontColor(1, 0.82, 0.2, 1);
  Line := Language.Translate('WEBQUEUE_QR_TITLE');
  SetFontPos((800 - TextWidth(Line)) / 2, 40);
  PrintText(Line);

  // the code itself, light background first so it stays scannable
  Renderer.DrawQuad(OriginX, OriginY, 0, Size, Size, 1, 1, 1, 1);

  for Y := 0 to QRCode.Size - 1 do
    for X := 0 to QRCode.Size - 1 do
      if QRCode.Dark[Y * QRCode.Size + X] then
        Renderer.DrawQuad(OriginX + (X + QuietZone) * Scale,
                          OriginY + (Y + QuietZone) * Scale, 0,
                          Scale, Scale, 0, 0, 0, 1);

  // address in clear text for everyone who would rather type it
  SetFontSize(27);
  SetFontColor(1, 1, 1, 1);
  Line := TruncateToWidth(Address, 780);
  SetFontPos((800 - TextWidth(Line)) / 2, OriginY + Size + 10);
  PrintText(Line);

  SetFontSize(18);
  SetFontColor(0.75, 0.75, 0.75, 1);
  Line := Language.Translate('WEBQUEUE_QR_HINT');
  SetFontPos((800 - TextWidth(Line)) / 2, OriginY + Size + 46);
  PrintText(Line);

  Renderer.DepthTest := true;
end;

procedure DrawWebQueueOverlay;
begin
  if (not Assigned(WebQueue)) or (not WebQueueEnabled) then
    Exit;

  // both would cover the lyrics, the singer knows what is being sung
  if Assigned(Display) and (Display.CurrentScreen = @ScreenSing) then
    Exit;

  if WebQueueOverlayVisible then
    DrawQueuePanel;

  if QRVisible then
    DrawQRPanel;
end;

end.
