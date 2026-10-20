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
    Played:     integer;   // how often it has been sung, from the score database
    PlayedToday:boolean;
    Duration:   integer;   // seconds up to the end of the last note, 0 if unknown
    IsDuet:     boolean;
    HasMedley:  boolean;    // has medley in/out tags, so it can be sung short
    Path:       UTF8String; // full path of the txt file, used to find the song again
    Cover:      UTF8String; // full path of the cover image, empty if there is none
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
    Short:   boolean;       // sing only the part between the medley tags
    Path:    UTF8String;
  end;
  TWebQueueEntryArray = array of TWebQueueEntry;

  {* One of the players of the running song, as shown on the player page. *}
  TWebPlayer = record
    Name:  UTF8String;
    Color: UTF8String;  // name of the microphone colour, e.g. Red
    RGB:   UTF8String;  // the same as #rrggbb, for the dot on the page
    Score: integer;
  end;
  TWebPlayerArray = array of TWebPlayer;

  TWebQueue = class
    private
      Lock:        TRTLCriticalSection;
      SongIndex:   TWebSongArray;
      Durations:   TStringList; // song id -> seconds, so a refresh does not read every file again
      PlayerInfo:  TWebPlayerArray;        // snapshot of the players, written once per frame
      PendingName: array of UTF8String;    // names the page asked for, applied on the main thread
      Singing:     boolean;
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
      procedure SongPlayed(const Artist, Title: UTF8String);

      {* Main thread, once per frame: hands over the names the page asked for
         and takes a snapshot of the players for it to show. *}
      procedure UpdatePlayers;
      procedure AddWish(const Wish, Singer: UTF8String);
      function  GetWishes: UTF8String;

      // the following methods are safe to call from the web server thread
      function  SearchSongs(const Search: UTF8String; Offset, Limit: integer;
                            const Sort: UTF8String; Desc: boolean; Seed: cardinal;
                            out Total: integer): TWebSongArray;
      function  SongCount: integer;
      function  CoverOf(SongID: cardinal): UTF8String;
      function  IndexReady: boolean;
      function  Enqueue(SongID: cardinal; const Singer: UTF8String; Short: boolean): boolean;
      function  RemoveEntry(EntryID: cardinal): boolean;
      function  MoveEntry(EntryID: cardinal; Offset: integer): boolean;
      function  Shuffle: boolean;
      function  GetPlayers(out IsSinging: boolean): TWebPlayerArray;
      function  SetPlayerName(Index: integer; const AName: UTF8String): boolean;
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

{* Shows/hides the picker that turns the queue into a medley. *}
procedure ToggleWebQueueMedleyPicker;
function  WebQueueMedleyPickerVisible: boolean;
procedure WebQueueMedleyAdjust(Delta: integer);
procedure WebQueueMedleyStart;
procedure CloseWebQueueMedleyPicker;

{* Shows/hides the big QR code of the song request address. *}
procedure ToggleWebQueueQRCode;
function  WebQueueQRCodeVisible: boolean;
procedure HideWebQueueQRCode;

implementation

uses
  DateUtils,
  Math,
  StrUtils,
  UCommon,
  UDataBase,
  UDisplay,
  UGraphic,
  UIni,
  ULanguage,
  ULog,
  UNote,
  UParty,
  UPath,
  UPathUtils,
  UPlatform,
  UPlaylist,
  UQRCode,
  UThemes,
  URenderer,
  sdl2,
  UScreenName,
  UScreenSong,
  USong,
  USongs,
  UText,
  UWebServer;

type
  {* One queue entry as offered in the medley picker. *}
  TWebMedleyCandidate = record
    Entry:    TWebQueueEntry;
    Eligible: boolean;
  end;
  TWebMedleyCandidateArray = array of TWebMedleyCandidate;

const
  // number of queue entries shown in the in-game overlay
  OverlayMaxEntries = 5;
  // checking medley data parses and analyses a song, so do not do it for a
  // whole party worth of requests at once
  MedleyPickerMaxSongs = 20;
  // upper bound for the queue, keeps a misbehaving client from filling memory
  WebQueueMaxLength = 100;

var
  // main thread only
  OverlayOverride: integer = -1; // -1: follow the config, 0: hidden, 1: shown
  StartRequested:  boolean = false;
  CachedRevision:  cardinal = 0;
  CachedEntries:   TWebQueueEntryArray;
  CacheValid:      boolean = false;

  MedleyPickerOpen:  boolean = false;
  MedleyRequested:   boolean = false;
  MedleyCandidates:  TWebMedleyCandidateArray;
  MedleyEligible:    integer = 0; // how many candidates can actually be sung
  MedleyCount:       integer = 0; // how many of them the user picked

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
  Durations := TStringList.Create;
  Durations.Sorted := true;
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
  Durations.Free;
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

function ColorToHex(const Col: TRGB): UTF8String;
begin
  Result := Format('#%.2x%.2x%.2x',
                   [Round(Col.R * 255), Round(Col.G * 255), Round(Col.B * 255)]);
end;

procedure TWebQueue.UpdatePlayers;
var
  I, Count, ColorNum: integer;
  Wanted: UTF8String;
begin
  Count := Min(PlayersPlay, Length(Player));

  EnterCriticalSection(Lock);
  try
    SetLength(PendingName, IMaxPlayerCount);
    for I := 0 to Count - 1 do
    begin
      Wanted := PendingName[I];
      if (Wanted <> '') then
      begin
        PendingName[I] := '';
        Player[I].Name := Wanted;
        // so the next song starts with the name as well
        Ini.Name[I] := Wanted;

        // the sing screen copies the names once when it opens
        if Assigned(ScreenSing) and (not Party.bPartyGame) then
        begin
          ScreenSing.PlayerNames[I + 1] := Wanted;
          ScreenSing.PlayerDuetNames[I + 1] := Wanted;
        end;
      end;
    end;

    Singing := Assigned(Display) and (Display.CurrentScreen = @ScreenSing);

    SetLength(PlayerInfo, Count);
    for I := 0 to Count - 1 do
    begin
      PlayerInfo[I].Name  := Player[I].Name;
      PlayerInfo[I].Score := Player[I].ScoreTotalInt;

      // the player colours have their own list, IColor is the one of the theme
      ColorNum := Ini.PlayerColor[I];
      if (ColorNum >= 1) and (ColorNum <= Length(IPlayerColorTranslated)) then
        PlayerInfo[I].Color := IPlayerColorTranslated[ColorNum - 1]
      else
        PlayerInfo[I].Color := '';
      PlayerInfo[I].RGB := ColorToHex(GetPlayerColor(ColorNum));
    end;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function TWebQueue.GetPlayers(out IsSinging: boolean): TWebPlayerArray;
begin
  EnterCriticalSection(Lock);
  try
    Result := Copy(PlayerInfo, 0, Length(PlayerInfo));
    IsSinging := Singing;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

{* The name is only parked here, the main thread picks it up in UpdatePlayers. *}
function TWebQueue.SetPlayerName(Index: integer; const AName: UTF8String): boolean;
begin
  Result := false;
  if (Trim(AName) = '') then
    Exit;

  EnterCriticalSection(Lock);
  try
    if (Index < 0) or (Index >= Length(PlayerInfo)) then
      Exit;

    SetLength(PendingName, IMaxPlayerCount);
    PendingName[Index] := Copy(Trim(AName), 1, 40);
    Result := true;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

{* Called on the main thread when a song has been sung, so the counts on the
   web page do not wait for the next rebuild of the index. *}
procedure TWebQueue.SongPlayed(const Artist, Title: UTF8String);
var
  I: integer;
begin
  EnterCriticalSection(Lock);
  try
    for I := 0 to High(SongIndex) do
      if (SongIndex[I].Artist = Artist) and (SongIndex[I].Title = Title) then
      begin
        Inc(SongIndex[I].Played);
        SongIndex[I].PlayedToday := true;
        Inc(fRevision);
        Break;
      end;
  finally
    LeaveCriticalSection(Lock);
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

{* Beat the last note of a song ends on. Only the tail of the file is read,
   the note lines are at the end and a big collection is read at startup. *}
function ReadLastNoteBeat(const TxtPath: UTF8String): integer;
const
  TailBytes = 8192;
var
  Stream: TBinaryFileStream;
  Buffer: RawByteString;
  Size:   int64;
  Lines:  TStringList;
  I, P:   integer;
  Line:   string;
  Parts:  TStringList;
begin
  Result := 0;

  try
    Stream := TBinaryFileStream.Create(Path(TxtPath), fmOpenRead);
  except
    Exit;
  end;

  Lines := TStringList.Create;
  Parts := TStringList.Create;
  try
    Size := Stream.Size;
    if (Size > TailBytes) then
    begin
      Stream.Seek(Size - TailBytes, soBeginning);
      SetLength(Buffer, TailBytes);
    end
    else
      SetLength(Buffer, Size);

    if (Length(Buffer) = 0) then
      Exit;

    Stream.Read(Buffer[1], Length(Buffer));
    Lines.Text := Buffer;

    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := false;

    for I := Lines.Count - 1 downto 0 do
    begin
      Line := Trim(Lines[I]);
      if (Length(Line) < 2) or (Pos(Line[1], ':*FRG') = 0) or (Line[2] <> ' ') then
        Continue;

      Parts.DelimitedText := Line;
      if (Parts.Count < 3) then
        Continue;

      P := StrToIntDef(Parts[1], -1);
      if (P < 0) then
        Continue;

      Result := P + Max(0, StrToIntDef(Parts[2], 0));
      Break;
    end;
  finally
    Parts.Free;
    Lines.Free;
    Stream.Free;
  end;
end;

procedure TWebQueue.RebuildSongIndex;
var
  I, Count: integer;
  CurSong:   TSong;
  NewIndex:  TWebSongArray;
  FullPath:  UTF8String;
  CoverPath: UTF8String;
  CoverFile: IPath;
  Cached:    integer;
  Seconds:   integer;
  LastPlayed: int64;
  Midnight:  int64;
begin
  Midnight := DateTimeToUnix(Trunc(Now));
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

    // #COVER is relative to the song folder and is never checked while parsing
    CoverPath := '';
    if (CurSong.Cover <> nil) and CurSong.Cover.IsSet then
    begin
      CoverFile := CurSong.Path.Append(CurSong.Cover);
      CoverFile := CoverFile.AdjustCase(false);
      if CoverFile.IsFile then
        CoverPath := CoverFile.ToUTF8();
    end;

    NewIndex[Count].ID         := WebQueueSongID(FullPath);
    NewIndex[Count].Artist     := CurSong.Artist;
    NewIndex[Count].Title      := CurSong.Title;
    NewIndex[Count].Language   := CurSong.Language;
    NewIndex[Count].Genre      := CurSong.Genre;
    NewIndex[Count].Edition    := CurSong.Edition;
    NewIndex[Count].Year       := CurSong.Year;
    NewIndex[Count].Played     := DataBase.GetTimesPlayed(CurSong.Artist, CurSong.Title);
    LastPlayed := DataBase.GetLastPlayed(CurSong.Artist, CurSong.Title);
    NewIndex[Count].PlayedToday := (LastPlayed >= Midnight);

    // the file is only read the first time a song shows up in the index
    if Durations.Find(IntToStr(NewIndex[Count].ID), Cached) then
      Seconds := PtrInt(Durations.Objects[Cached])
    else
    begin
      Seconds := Max(0, Round(GetTimeFromBeat(ReadLastNoteBeat(FullPath), CurSong)));
      Durations.AddObject(IntToStr(NewIndex[Count].ID), TObject(PtrInt(Seconds)));
    end;
    NewIndex[Count].Duration := Seconds;
    NewIndex[Count].IsDuet     := CurSong.isDuet;
    // only the explicit tags, a guessed refrain is not what the guest picked
    NewIndex[Count].HasMedley  := (CurSong.Medley.Source >= msTag);
    NewIndex[Count].Path       := FullPath;
    NewIndex[Count].Cover      := CoverPath;
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

{* Levenshtein distance, stopped as soon as it is clear that it exceeds Limit. *}
function EditDistance(const A, B: UTF8String; Limit: integer): integer;
var
  Prev, Cur: array of integer;
  I, J, Best, Cost: integer;
begin
  if (Abs(Length(A) - Length(B)) > Limit) then
  begin
    Result := Limit + 1;
    Exit;
  end;

  SetLength(Prev, Length(B) + 1);
  SetLength(Cur, Length(B) + 1);
  for J := 0 to Length(B) do
    Prev[J] := J;

  for I := 1 to Length(A) do
  begin
    Cur[0] := I;
    Best := Cur[0];
    for J := 1 to Length(B) do
    begin
      Cost := IfThen(A[I] = B[J], 0, 1);
      Cur[J] := Min(Min(Cur[J - 1] + 1, Prev[J] + 1), Prev[J - 1] + Cost);
      Best := Min(Best, Cur[J]);
    end;

    if (Best > Limit) then
    begin
      Result := Limit + 1;
      Exit;
    end;

    Prev := Copy(Cur, 0, Length(Cur));
  end;

  Result := Prev[Length(B)];
end;

{* True if Word is close enough to one of the words in Haystack to be a typo
   of it. Short words have to be spelled right, otherwise everything matches. *}
function FuzzyMatch(const Haystack, Word: UTF8String): boolean;
var
  Words: TStringList;
  I, Limit: integer;
begin
  Result := false;
  if (Length(Word) < 4) then
    Exit;

  Limit := IfThen(Length(Word) <= 6, 1, 2);

  Words := TStringList.Create;
  try
    Words.Delimiter := ' ';
    Words.StrictDelimiter := true;
    Words.DelimitedText := Haystack;

    for I := 0 to Words.Count - 1 do
      if (EditDistance(Word, Words[I], Limit) <= Limit) then
      begin
        Result := true;
        Exit;
      end;
  finally
    Words.Free;
  end;
end;

{* Key a song is sorted by on the web page. Everything is a string so one
   compare serves all four orders. *}
function SongSortKey(const Song: TWebSong; const Sort: UTF8String; Seed: cardinal;
                    Desc: boolean): UTF8String;
begin
  if (Sort = 'title') then
    Result := LowerCase(Song.Title) + #1 + LowerCase(Song.Artist)
  else if (Sort = 'year') then
  begin
    // songs without a year belong at the end of the list either way round
    if (Song.Year <= 0) then
      Result := IfThen(Desc, '00000', '99999')
    else
      Result := Format('%.5d', [Song.Year]);
    Result := Result + #1 + LowerCase(Song.Artist) + #1 + LowerCase(Song.Title);
  end
  else if (Sort = 'played') then
    Result := Format('%.5d', [Min(Song.Played, 99999)]) + #1 +
              LowerCase(Song.Artist) + #1 + LowerCase(Song.Title)
  else if (Sort = 'random') then
    // derived from the seed, so the order stays put while the page asks for
    // further pages and only changes when it sends a new seed
    Result := IntToHex(WebQueueSongID(IntToStr(Seed) + '/' + IntToStr(Song.ID)), 8)
  else
    Result := LowerCase(Song.Artist) + #1 + LowerCase(Song.Title);
end;

function TWebQueue.SearchSongs(const Search: UTF8String; Offset, Limit: integer;
                               const Sort: UTF8String; Desc: boolean; Seed: cardinal;
                               out Total: integer): TWebSongArray;
var
  I, Added:  integer;
  Matches:   array of integer;
  MatchCnt:  integer;
  Needle:    UTF8String;
  Words:     TStringList;
  Order:     TStringList;
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
        if (Words[W] <> '') and (Pos(Words[W], SongIndex[I].SearchText) = 0) and
           (not FuzzyMatch(SongIndex[I].SearchText, Words[W])) then
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

    if (Sort <> '') then
    begin
      Order := TStringList.Create;
      try
        Order.Capacity := MatchCnt;
        for I := 0 to MatchCnt - 1 do
          Order.AddObject(SongSortKey(SongIndex[Matches[I]], Sort, Seed, Desc),
                          TObject(PtrInt(Matches[I])));
        Order.Sort;

        for I := 0 to MatchCnt - 1 do
          if Desc then
            Matches[MatchCnt - 1 - I] := PtrInt(Order.Objects[I])
          else
            Matches[I] := PtrInt(Order.Objects[I]);
      finally
        Order.Free;
      end;
    end;

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

function TWebQueue.CoverOf(SongID: cardinal): UTF8String;
var
  Index: integer;
begin
  Result := '';

  EnterCriticalSection(Lock);
  try
    Index := FindSongIndex(SongID);
    if (Index >= 0) then
      Result := SongIndex[Index].Cover;
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

function TWebQueue.Enqueue(SongID: cardinal; const Singer: UTF8String; Short: boolean): boolean;
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
    Entries[Len].Short   := Short and SongIndex[SongIdx].HasMedley;

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

function SingerCount(const Pool: TWebQueueEntryArray; const Singer: UTF8String): integer;
var
  I: integer;
begin
  Result := 0;
  for I := 0 to High(Pool) do
    if (Pool[I].Singer = Singer) then
      Inc(Result);
end;

{* Shuffles the queue so that nobody sings three songs in a row. Picking the
   singer with the most songs left is what keeps the one who requested half the
   queue from piling up at the end; the order is still random because the pool
   is shuffled first. *}
function TWebQueue.Shuffle: boolean;
var
  Pool, Mixed: TWebQueueEntryArray;
  Swap: TWebQueueEntry;
  I, J, Pick, Count, Best: integer;
begin
  Result := false;

  EnterCriticalSection(Lock);
  try
    if (Length(Entries) < 2) then
      Exit;

    Pool := Copy(Entries, 0, Length(Entries));
    for I := High(Pool) downto 1 do
    begin
      J := Random(I + 1);
      Swap := Pool[I]; Pool[I] := Pool[J]; Pool[J] := Swap;
    end;

    SetLength(Mixed, 0);
    while (Length(Pool) > 0) do
    begin
      Pick := -1;
      Best := -1;
      for I := 0 to High(Pool) do
      begin
        if (Length(Mixed) >= 2) and
           (Pool[I].Singer = Mixed[High(Mixed)].Singer) and
           (Pool[I].Singer = Mixed[High(Mixed) - 1].Singer) then
          Continue;

        Count := SingerCount(Pool, Pool[I].Singer);
        if (Count > Best) then
        begin
          Best := Count;
          Pick := I;
        end;
      end;

      // everything left is the same singer, the rule cannot be kept
      if (Pick < 0) then
        Pick := 0;

      SetLength(Mixed, Length(Mixed) + 1);
      Mixed[High(Mixed)] := Pool[Pick];

      for I := Pick to High(Pool) - 1 do
        Pool[I] := Pool[I + 1];
      SetLength(Pool, Length(Pool) - 1);
    end;

    Entries := Mixed;
    Inc(fRevision);
    Result := true;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

{* Tabs and line breaks would turn one wish into several lines. *}
function OneLine(const Text: UTF8String): UTF8String;
begin
  Result := Trim(StringReplace(StringReplace(StringReplace(Text,
              #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]), #9, ' ', [rfReplaceAll]));
end;

{* A song somebody missed in the list. Appended to a file so it can be read
   after the party, the queue itself does not know the song. *}
procedure TWebQueue.AddWish(const Wish, Singer: UTF8String);
var
  Target: IPath;
  Line:   UTF8String;
  Stream: TBinaryFileStream;
begin
  if (Trim(Wish) = '') then
    Exit;

  // next to config.ini and the score database, not in the program directory
  Target := Platform.GetGameUserPath.Append('song-requests.txt');
  // one wish is one line with three fields, whatever the client sent
  Line := FormatDateTime('yyyy-mm-dd hh:nn', Now) + #9 +
          IfThen(Trim(Singer) = '', '-', OneLine(Singer)) + #9 + OneLine(Wish) + LineEnding;

  EnterCriticalSection(Lock);
  try
    if Target.IsFile then
    begin
      Stream := TBinaryFileStream.Create(Target, fmOpenWrite);
      Stream.Seek(0, soEnd);
    end
    else
      Stream := TBinaryFileStream.Create(Target, fmCreate);
  except
    Log.LogError('Could not write ' + Target.ToNative, 'TWebQueue.AddWish');
    LeaveCriticalSection(Lock);
    Exit;
  end;

  try
    Stream.Write(Line[1], Length(Line));
  finally
    Stream.Free;
    LeaveCriticalSection(Lock);
  end;

  Log.LogStatus('Song request: ' + Line, 'TWebQueue.AddWish');
end;

{* The whole wish file, as it is written. The page splits it into lines. *}
function TWebQueue.GetWishes: UTF8String;
var
  Target: IPath;
  Stream: TBinaryFileStream;
  Size:   int64;
begin
  Result := '';

  Target := Platform.GetGameUserPath.Append('song-requests.txt');
  if not Target.IsFile then
    Exit;

  EnterCriticalSection(Lock);
  try
    try
      Stream := TBinaryFileStream.Create(Target, fmOpenRead);
    except
      Exit;
    end;

    try
      Size := Stream.Size;
      if (Size <= 0) then
        Exit;

      SetLength(Result, Size);
      Stream.Read(Result[1], Size);
    finally
      Stream.Free;
    end;
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

    if Entry.Short and ScreenSong.EnsureMedleyData(CatIndex, msTag) then
    begin
      // a medley of exactly one song is the short version: USDX then sings
      // only the part between the medley in and out tags
      SetLength(PlaylistMedley.Song, 1);
      PlaylistMedley.Song[0] := CatIndex;
      PlaylistMedley.NumMedleySongs := 1;
      ScreenSong.Mode := smMedley;
      ScreenSong.StopMusicPreview();
      Display.FadeTo(@ScreenSing);
    end
    else
      ScreenSong.StartSong;

    QRVisible := false;

    Log.LogStatus('Starting queued song' + IfThen(Entry.Short, ' (short)', '') + ': ' +
                  Entry.Artist + ' - ' + Entry.Title,
                  'UWebQueue.StartNextQueuedSong');

    Result := true;
    Exit;
  end;
end;

{**
 * Collects the queued songs that USDX can actually medley. Deciding that means
 * parsing and analysing each song, which is why the list is capped.
 *}
procedure OpenMedleyPicker;
var
  Entries: TWebQueueEntryArray;
  I, Idx, Count: integer;
begin
  Entries := WebQueue.GetEntries;

  Count := Length(Entries);
  if (Count > MedleyPickerMaxSongs) then
    Count := MedleyPickerMaxSongs;

  SetLength(MedleyCandidates, Count);
  MedleyEligible := 0;

  for I := 0 to Count - 1 do
  begin
    MedleyCandidates[I].Entry := Entries[I];

    Idx := FindCatSongIndex(Entries[I]);
    MedleyCandidates[I].Eligible :=
      (Idx >= 0) and ScreenSong.EnsureMedleyData(Idx, msCalculated);

    if MedleyCandidates[I].Eligible then
      Inc(MedleyEligible);
  end;

  MedleyCount      := MedleyEligible;
  MedleyPickerOpen := true;
end;

procedure CloseWebQueueMedleyPicker;
begin
  MedleyPickerOpen := false;
  SetLength(MedleyCandidates, 0);
end;

procedure ToggleWebQueueMedleyPicker;
begin
  if MedleyPickerOpen then
    CloseWebQueueMedleyPicker
  else if Assigned(WebQueue) and Assigned(ScreenSong) and (WebQueue.Count > 0) then
    OpenMedleyPicker;
end;

function WebQueueMedleyPickerVisible: boolean;
begin
  Result := MedleyPickerOpen;
end;

procedure WebQueueMedleyAdjust(Delta: integer);
begin
  if (not MedleyPickerOpen) or (MedleyEligible = 0) then
    Exit;

  MedleyCount := MedleyCount + Delta;
  if (MedleyCount < 1) then
    MedleyCount := 1;
  if (MedleyCount > MedleyEligible) then
    MedleyCount := MedleyEligible;
end;

procedure WebQueueMedleyStart;
begin
  if (not MedleyPickerOpen) or (MedleyEligible = 0) then
    Exit;

  MedleyPickerOpen := false;
  MedleyRequested  := true;
end;

{**
 * Fills PlaylistMedley from the picked songs and starts singing. Must run
 * after TScreenSong.OnShow, which wipes that list and resets the mode.
 *}
function StartQueuedMedley: boolean;
var
  I, Idx, Taken: integer;
begin
  Result := false;

  // may rebuild CatSongs.Song, so the indices have to be looked up afterwards
  ResetSongView;

  Taken := 0;
  SetLength(PlaylistMedley.Song, 0);

  for I := 0 to High(MedleyCandidates) do
  begin
    if (Taken >= MedleyCount) then
      Break;
    if (not MedleyCandidates[I].Eligible) then
      Continue;

    Idx := FindCatSongIndex(MedleyCandidates[I].Entry);
    if (Idx < 0) then
      Continue;

    SetLength(PlaylistMedley.Song, Taken + 1);
    PlaylistMedley.Song[Taken] := Idx;
    Inc(Taken);
  end;

  if (Taken = 0) then
  begin
    Log.LogWarn('No queued song has medley data', 'UWebQueue.StartQueuedMedley');
    Exit;
  end;

  PlaylistMedley.NumMedleySongs := Taken;
  ScreenSong.MakeMedley := false;
  ScreenSong.Mode := smMedley;

  Log.LogStatus(Format('Starting medley of %d queued songs', [Taken]),
                'UWebQueue.StartQueuedMedley');

  Display.FadeTo(@ScreenSing);
  SetLength(MedleyCandidates, 0);
  QRVisible := false;

  Result := true;
end;

procedure ProcessWebQueueRequest;
begin
  if Assigned(WebQueue) then
    WebQueue.UpdatePlayers;

  if (not StartRequested) and (not MedleyRequested) then
    Exit;

  if (not Assigned(WebQueue)) or (not Assigned(Display)) or (not Assigned(ScreenSong)) then
  begin
    StartRequested := false;
    Exit;
  end;

  // nothing left to start
  if (WebQueue.Count = 0) then
  begin
    StartRequested  := false;
    MedleyRequested := false;
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
    StartRequested  := false;
    MedleyRequested := false;
    Log.LogInfo('Song request ignored while the editor is open', 'UWebQueue.ProcessWebQueueRequest');
    Exit;
  end;

  // a running party game has its own song selection, do not interfere
  if Party.bPartyGame then
  begin
    StartRequested  := false;
    MedleyRequested := false;
    Log.LogWarn('Song request ignored, a party game is running', 'UWebQueue.ProcessWebQueueRequest');
    Exit;
  end;

  // The sing and score screens are built by the player name screen and need
  // the avatars and colours it prepares. Send the host there once, the next
  // request then starts the song right away.
  if (not Assigned(ScreenSing)) or (not Assigned(ScreenScore)) then
  begin
    StartRequested  := false;
    MedleyRequested := false;
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
    if MedleyRequested then
    begin
      MedleyRequested := false;
      StartQueuedMedley;
    end
    else
    begin
      StartRequested := false;
      StartNextQueuedSong;
    end;
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

{* A line that does not fit scrolls sideways and back, so the singer name at
   the end of a long entry can be read. Scrolling by whole characters keeps
   this to plain string work, no clipping needed. *}
function ScrollToWidth(const Text: UTF8String; MaxWidth: real): UTF8String;
var
  Starts: array of integer; // byte index of every character start
  I, MaxCut, Cut, Len: integer;
  T, Travel, Rest, Cycle: cardinal;
const
  // how long the line rests at each end, and per character on the way
  RestMs = 1500;
  StepMs = 140;
begin
  Result := Text;
  if (TextWidth(Result) <= MaxWidth) then
    Exit;

  SetLength(Starts, 0);
  for I := 1 to Length(Text) do
    if (Ord(Text[I]) and $C0 <> $80) then
    begin
      SetLength(Starts, Length(Starts) + 1);
      Starts[High(Starts)] := I;
    end;

  // characters that have to go before the end of the line fits
  MaxCut := 0;
  while (MaxCut < High(Starts)) and
        (TextWidth(Copy(Text, Starts[MaxCut], MaxInt)) > MaxWidth) do
    Inc(MaxCut);

  if (MaxCut = 0) then
    Exit;

  Rest   := RestMs;
  Travel := Max(600, cardinal(MaxCut) * StepMs);
  Cycle  := 2 * (Rest + Travel);
  T      := SDL_GetTicks mod Cycle;

  if (T < Rest) then
    Cut := 0
  else if (T < Rest + Travel) then
    Cut := Round(MaxCut * (T - Rest) / Travel)
  else if (T < 2 * Rest + Travel) then
    Cut := MaxCut
  else
    Cut := MaxCut - Round(MaxCut * (T - 2 * Rest - Travel) / Travel);

  Result := Copy(Text, Starts[Cut], MaxInt);

  // whatever still sticks out on the right is cut, the movement shows there
  // is more to come
  Len := Length(Result);
  while (Len > 1) and (TextWidth(Copy(Result, 1, Len)) > MaxWidth) do
  begin
    Dec(Len);
    while (Len > 1) and (Ord(Result[Len + 1]) and $C0 = $80) do
      Dec(Len);
  end;
  Result := Copy(Result, 1, Len);
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
      if CachedEntries[I].Short then
        Line := Line + ' (' + Language.Translate('WEBQUEUE_SHORT') + ')';
      if (CachedEntries[I].Singer <> '') then
        Line := Line + ' [' + CachedEntries[I].Singer + ']';

      SetFontPos(PanelX + 6, LineY);
      PrintText(ScrollToWidth(Line, PanelW - 12));
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

{**
 * The medley picker: every queued song with whether it can be sung in a medley,
 * and how many of them to use.
 *}
procedure DrawMedleyPicker;
var
  I, Shown, Taken: integer;
  PanelX, PanelY, PanelW, PanelH, LineY: real;
  Line: UTF8String;
const
  LineHeight = 17;
  HeaderHeight = 30;
begin
  Shown := Length(MedleyCandidates);

  PanelW := 560;
  PanelH := HeaderHeight + LineHeight * (Shown + 2) + 18;
  PanelX := (800 - PanelW) / 2;
  PanelY := (600 - PanelH) / 2;

  Renderer.DepthTest := false;
  Renderer.DrawQuad(0, 0, 0, 800, 600, 0, 0, 0, 0.7);
  Renderer.DrawQuad(PanelX, PanelY, 0, PanelW, PanelH, 0.07, 0.08, 0.12, 0.96);

  SetFontFamily(0);
  SetFontStyle(ftRegular);
  SetFontItalic(false);
  SetFontReflection(false, 0);

  SetFontSize(21);
  SetFontColor(1, 0.82, 0.2, 1);
  SetFontPos(PanelX + 12, PanelY + 6);
  PrintText(Language.Translate('WEBQUEUE_MEDLEY_TITLE'));

  SetFontSize(15);
  LineY := PanelY + HeaderHeight;
  Taken := 0;

  for I := 0 to Shown - 1 do
  begin
    if MedleyCandidates[I].Eligible and (Taken < MedleyCount) then
    begin
      Inc(Taken);
      SetFontColor(1, 1, 1, 1);
      Line := IntToStr(Taken) + '. ';
    end
    else if MedleyCandidates[I].Eligible then
    begin
      SetFontColor(0.6, 0.6, 0.6, 1);
      Line := '-  ';
    end
    else
    begin
      SetFontColor(0.55, 0.4, 0.4, 1);
      Line := '-  ';
    end;

    Line := Line + MedleyCandidates[I].Entry.Artist + ' - ' + MedleyCandidates[I].Entry.Title;
    if (not MedleyCandidates[I].Eligible) then
      Line := Line + '  (' + Language.Translate('WEBQUEUE_MEDLEY_SKIP') + ')';

    SetFontPos(PanelX + 12, LineY);
    PrintText(TruncateToWidth(Line, PanelW - 24));
    LineY := LineY + LineHeight;
  end;

  LineY := LineY + LineHeight * 0.4;

  if (MedleyEligible = 0) then
  begin
    SetFontColor(1, 0.6, 0.4, 1);
    Line := Language.Translate('WEBQUEUE_MEDLEY_NONE');
  end
  else
  begin
    SetFontColor(1, 0.82, 0.2, 1);
    Line := Format(Language.Translate('WEBQUEUE_MEDLEY_COUNT'), [MedleyCount, MedleyEligible]);
  end;

  SetFontSize(17);
  SetFontPos(PanelX + 12, LineY);
  PrintText(TruncateToWidth(Line, PanelW - 24));

  SetFontSize(14);
  SetFontColor(0.7, 0.7, 0.7, 1);
  SetFontPos(PanelX + 12, LineY + LineHeight + 2);
  PrintText(TruncateToWidth(Language.Translate('WEBQUEUE_MEDLEY_HINT'), PanelW - 24));

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

  if MedleyPickerOpen then
    DrawMedleyPicker;
end;

end.
