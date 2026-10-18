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
 *
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/screens/UScreenOptionsGame.pas $
 * $Id: UScreenOptionsGame.pas 2203 2010-03-16 19:25:13Z brunzelchen $
 *}

unit UScreenOptionsGame;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UDisplay,
  UFiles,
  UIni,
  UMenu,
  UMusic,
  UScreensong,
  USongs,
  UThemes,
  sdl2;

type
  TScreenOptionsGame = class(TOptionsMenu)
    private
      old_Language:  integer;
      old_SongMenu:  integer;
      old_Sorting:   integer;
      old_Tabs:      integer;
      AVDelayOptInt: integer;
      MicDelayOptInt:integer;
      AVDelaySelectNum:  integer;
      MicDelaySelectNum: integer;

      // microphone delay calibration, see StartCalibration
      CalPhase:     integer;
      CalRound:     integer;
      CalStart:     cardinal;
      CalNoise:     single;
      CalThreshold: single;
      CalPlayers:   integer;
      CalCapturing: boolean;
      CalResults:   array of integer;
      CalMessage:   UTF8String;

      procedure StartCalibration;
      procedure NextCalibrationRound;
      procedure StopCalibration(const Message: UTF8String);
      procedure UpdateCalibration;
      procedure DrawCalibration;

      procedure Leave;
      procedure ReloadCurrentScreen;
      procedure ReloadAllScreens;
      procedure ReloadSongMenu;
      procedure UpdateCalculatedSelectSlides(Init: boolean);

    protected
      procedure LoadWidgets; override;

    public
      constructor Create; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean; override;
      function Draw: boolean; override;
      procedure OnShow; override;
  end;

const
  ID='ID_071';   //for help system

  CalibrationRounds    = 5;    // median over this many clicks
  CalibrationNoiseMs   = 500;  // listen to the room before the first click
  CalibrationPauseMs   = 450;  // silence between two clicks
  CalibrationTimeoutMs = 1500;
  CalibrationHeadroom  = 0.10; // how far above the room noise counts as the click

implementation

uses
  StrUtils,
  UConfig,
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  UNote,
  URecord,
  URenderer,
  UText,
  UUnicodeUtils,
  SysUtils;

type
  TGetTextFunc = function(var Param: integer; Offset: integer; Modify: boolean; OptText: PUtf8String): boolean;
  UTF8StringArray = array of UTF8String;
  InteractionID = (
    iLanguageSlide,
    iSongMenuSlide,
    iTabsSlide,
    iSortingSlide,
    iShowScoresSlide,
    iDebugSlide,
    iAVDelaySlide,
    iMicDelaySlide,
    iBackButton
  );

function TScreenOptionsGame.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean;
begin
  Result := true;
  if PressedDown then
  begin // Key Down
    // check normal keys
    case PressedKey of
      SDLK_Q:
        begin
          Result := false;
          Exit;
        end;
      SDLK_C:
        begin
          if (CalPhase = 0) then
            StartCalibration
          else
            StopCalibration('');
          Exit;
        end;
    end;

    // check special keys
    case PressedKey of
      SDLK_ESCAPE,
      SDLK_BACKSPACE :
        begin
          if (CalPhase <> 0) then
            StopCalibration('')
          else
            Leave;
        end;
      SDLK_TAB:
        begin
          ScreenPopupHelp.ShowPopup();
        end;
      SDLK_RETURN:
        begin
          if SelInteraction = ord(iBackButton) then
            Leave;
        end;
      SDLK_DOWN:
        InteractNext;
      SDLK_UP :
        InteractPrev;
      SDLK_RIGHT:
        begin
          if Interactions[SelInteraction].Typ = iSelectS then
          begin
            AudioPlayback.PlaySound(SoundLib.Option);
            InteractInc;
          end;
          UpdateCalculatedSelectSlides(false);
          if (SelInteraction = ord(iLanguageSlide)) then
          begin
            ReloadCurrentScreen;
          end;
        end;
      SDLK_LEFT:
        begin
          if Interactions[SelInteraction].Typ = iSelectS then
          begin
            AudioPlayback.PlaySound(SoundLib.Option);
            InteractDec;
          end;
          UpdateCalculatedSelectSlides(false);
          if (SelInteraction = ord(iLanguageSlide)) then
          begin
            ReloadCurrentScreen;
          end;
        end;
    end;
  end;
end;

procedure CalculateSelectSlide(Init: boolean; GetText: TGetTextFunc; var Param: integer; var OptInt: integer; var Texts: UTF8StringArray);
var
  Idx: integer;
  NumOpts: integer;
begin
  if not GetText(Param, 0, true, nil) then
  begin
    SetLength(Texts, 0);
    Exit;
  end;
  if GetText(Param, -1, false, nil) then
    Idx := 1
  else
    Idx := 0;
  if not Init then
  begin
    if OptInt = Idx then
      Exit;
    GetText(Param, OptInt - Idx, true, nil);
    if GetText(Param, -1, false, nil) then
      Idx := 1
    else
      Idx := 0;
  end;
  OptInt := Idx;
  if GetText(Param, 1, false, nil) then
    NumOpts := Idx + 2
  else
    NumOpts := Idx + 1;
  SetLength(Texts, NumOpts);
  for Idx := 0 to High(Texts) do
    GetText(Param, Idx - OptInt, false, @Texts[Idx]);
end;

function GetAVDelayOptText(var Param: integer; Offset: integer; Modify: boolean; OptText: PUTF8String): boolean;
begin
  if OptText <> nil then
    OptText^ := Format('%d ms', [Param + Offset * 10]);
  if Modify then
    Param := Param + Offset * 10;
  Result := true;
end;

function GetMicDelayOptText(var Param: integer; Offset: integer; Modify: boolean; OptText: PUTF8String): boolean;
begin
  if Param + Offset * 10 < 0 then
    Result := false
  else
  begin
    if OptText <> nil then
      OptText^ := Format('%d ms', [Param + Offset * 10]);
    if Modify then
      Param := Param + Offset * 10;
    Result := true;
  end;
end;

{**
 * Measures how long the sound of the game needs to come back through the
 * microphone: it plays a short click and waits for the microphone to hear it.
 * The round trip covers the output buffer, a bluetooth or airplay speaker and
 * the microphone, which is what the mic delay has to compensate.
 *
 * The median of several rounds is used, a single round is easily spoiled by a
 * door falling shut.
 *}
procedure TScreenOptionsGame.StartCalibration;
begin
  CalMessage := '';

  if (AudioInputProcessor.CheckPlayersConfig(1) <> 0) then
  begin
    CalMessage := Language.Translate('RECORD_CALIBRATE_NO_DEVICE');
    Exit;
  end;

  // the menu music comes out of the same speakers and would both lift the
  // noise floor and mask the click
  SoundLib.PauseBgMusic;

  // the capture is wired up per player, borrow player one for the measurement
  CalPlayers := PlayersPlay;
  PlayersPlay := 1;
  AudioInput.CaptureStart;
  CalCapturing := true;

  SetLength(CalResults, 0);
  CalRound := 0;
  CalNoise := 0;
  CalStart := SDL_GetTicks;
  CalPhase := 1; // listen to the room first
end;

procedure TScreenOptionsGame.NextCalibrationRound;
begin
  Inc(CalRound);

  // drop what is still in the analysis window, otherwise the previous click
  // triggers the next round right away
  AudioInputProcessor.Sound[0].Clear();

  AudioPlayback.PlaySound(SoundLib.Click);
  CalStart := SDL_GetTicks;
  CalPhase := 2;
end;

procedure TScreenOptionsGame.StopCalibration(const Message: UTF8String);
begin
  if CalCapturing then
  begin
    AudioInput.CaptureStop;
    PlayersPlay := CalPlayers;
    CalCapturing := false;

    // only resumes when the setting asks for it
    SoundLib.StartBgMusic;
  end;

  CalPhase   := 0;
  CalMessage := Message;
end;

procedure TScreenOptionsGame.UpdateCalibration;
var
  Now, Elapsed: cardinal;
  Level: single;
  I, J, Swap: integer;
  RoundTrip: integer;
  Line: UTF8String;
begin
  if (CalPhase = 0) then
    Exit;

  Now   := SDL_GetTicks;
  Level := AudioInputProcessor.Sound[0].MaxSampleVolume();

  case CalPhase of
    1: // how loud is the room on its own
      begin
        if (Level > CalNoise) then
          CalNoise := Level;

        if (Now - CalStart >= CalibrationNoiseMs) then
        begin
          CalThreshold := CalNoise + CalibrationHeadroom;
          if (CalThreshold > 0.8) then
          begin
            StopCalibration(Language.Translate('RECORD_CALIBRATE_TOO_LOUD'));
            Exit;
          end;
          NextCalibrationRound;
        end;
      end;

    2: // waiting for the click to come back
      begin
        Elapsed := Now - CalStart;

        if (Level >= CalThreshold) then
        begin
          SetLength(CalResults, Length(CalResults) + 1);
          CalResults[High(CalResults)] := Elapsed;
          CalStart := Now;
          CalPhase := 3;
        end
        else if (Elapsed > CalibrationTimeoutMs) then
          StopCalibration(Language.Translate('RECORD_CALIBRATE_NOT_HEARD'));
      end;

    3: // let the room go quiet again
      begin
        if (Now - CalStart < CalibrationPauseMs) then
          Exit;

        if (CalRound < CalibrationRounds) then
        begin
          NextCalibrationRound;
          Exit;
        end;

        for I := 0 to High(CalResults) - 1 do
          for J := 0 to High(CalResults) - I - 1 do
            if (CalResults[J] > CalResults[J+1]) then
            begin
              Swap := CalResults[J];
              CalResults[J] := CalResults[J+1];
              CalResults[J+1] := Swap;
            end;

        Line := '';
        for J := 0 to High(CalResults) do
          Line := Line + IfThen(J > 0, ', ', '') + IntToStr(CalResults[J]);

        // median, rounded to the 10ms steps the setting uses
        RoundTrip := Round(CalResults[Length(CalResults) div 2] / 10) * 10;

        // The click goes out through the speakers and comes back in through the
        // microphone, so this is the whole round trip. AVDelay already shifts
        // the lyrics by the output half of it, and compensating for that half
        // twice would score every note early.
        I := RoundTrip - Ini.AVDelay;
        if (I < 0) then
          I := 0;

        Ini.MicDelay := I;

        // the update path of CalculateSelectSlide reads the value back out of
        // the widget, so rebuild the option window from the new value instead
        CalculateSelectSlide(true, @GetMicDelayOptText, Ini.MicDelay, MicDelayOptInt, IMicDelay);
        UpdateSelectSlideOptions(MicDelaySelectNum, IMicDelay, MicDelayOptInt);

        Log.LogStatus(Format('Round trip %d ms minus AV delay %d ms, microphone delay set to %d ms ' +
                             '(rounds sorted: %s, noise %.2f, threshold %.2f)',
                             [RoundTrip, Ini.AVDelay, I, Line, CalNoise, CalThreshold]),
                      'TScreenOptionsGame.UpdateCalibration');

        StopCalibration(Format(Language.Translate('RECORD_CALIBRATE_RESULT'), [RoundTrip, I]));
      end;
  end;
end;

procedure TScreenOptionsGame.DrawCalibration;
var
  Line: UTF8String;
  X, Y, W: real;
begin
  if (MicDelaySelectNum < 0) or (MicDelaySelectNum > High(SelectsS)) then
    Exit;

  // sit right under the mic delay setting this is about
  X := SelectsS[MicDelaySelectNum].Texture.X;
  Y := SelectsS[MicDelaySelectNum].Texture.Y + SelectsS[MicDelaySelectNum].Texture.H + 1;
  W := SelectsS[MicDelaySelectNum].TextureSBG.X
     + SelectsS[MicDelaySelectNum].TextureSBG.W - X;

  Renderer.DepthTest := false;

  SetFontFamily(0);
  SetFontStyle(ftRegular);
  SetFontItalic(false);
  SetFontReflection(false, 0);
  SetFontSize(14);

  if (CalPhase = 0) and (CalMessage = '') then
  begin
    SetFontColor(0.75, 0.75, 0.75, 1);
    SetFontPos(X + 4, Y);
    PrintText(Language.Translate('RECORD_CALIBRATE_HINT'));
    Renderer.DepthTest := true;
    Exit;
  end;

  Renderer.DrawQuad(X, Y - 1, 0, W, 22, 0, 0, 0, 0.8);

  case CalPhase of
    1: Line := Language.Translate('RECORD_CALIBRATE_QUIET');
    2, 3: Line := Format(Language.Translate('RECORD_CALIBRATE_RUNNING'),
                         [CalRound, CalibrationRounds]);
    else Line := CalMessage;
  end;

  if (CalPhase = 0) then
    SetFontColor(0.6, 1, 0.7, 1)
  else
    SetFontColor(1, 0.82, 0.2, 1);

  SetFontPos(X + 4, Y);
  PrintText(Line);

  Renderer.DepthTest := true;
end;

function TScreenOptionsGame.Draw: boolean;
begin
  UpdateCalibration;
  Result := inherited Draw;
  DrawCalibration;
end;

procedure TScreenOptionsGame.UpdateCalculatedSelectSlides(Init: boolean);
begin
  CalculateSelectSlide(Init, @GetAVDelayOptText, Ini.AVDelay, AVDelayOptInt, IAVDelay);
  CalculateSelectSlide(Init, @GetMicDelayOptText, Ini.MicDelay, MicDelayOptInt, IMicDelay);
  if Init then
  begin
    AVDelaySelectNum := AddSelectSlide('SING_OPTIONS_GAME_AVDELAY', AVDelayOptInt, IAVDelay);
    MicDelaySelectNum := AddSelectSlide('SING_OPTIONS_GAME_MICDELAY', MicDelayOptInt, IMicDelay);
  end
  else
  begin
    UpdateSelectSlideOptions(AVDelaySelectNum, IAVDelay, AVDelayOptInt);
    UpdateSelectSlideOptions(MicDelaySelectNum, IMicDelay, MicDelayOptInt);
  end;
end;

constructor TScreenOptionsGame.Create;
begin
  inherited Create;
  Description := Language.Translate('SING_OPTIONS_GAME_DESC');
  WhereAmI := Language.Translate('SING_OPTIONS_GAME_WHEREAMI');
  Load;
end;

procedure TScreenOptionsGame.OnShow;
begin
  inherited;

  // save current settings in order to determine if a refresh is required
  old_Language := Ini.Language;
  old_SongMenu := Ini.SongMenu;
  old_Sorting  := Ini.Sorting;
  old_Tabs     := Ini.Tabs;

  Interaction := 0;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenOptionsGame');
end;

procedure TScreenOptionsGame.Leave;
begin
  StopCalibration('');

  Ini.Save;
  ReloadAllScreens;
  ReloadSongMenu;

  AudioPlayback.PlaySound(SoundLib.Back);
  FadeTo(@ScreenOptions);
end;

procedure TScreenOptionsGame.ReloadCurrentScreen;
begin
  ScreenOptionsGame.Free;
  Language.ChangeLanguage(ILanguage[Ini.Language]);
  Ini.TranslateOptionValues;
  Theme.LoadTheme(Ini.Theme, Ini.Color);
  ScreenOptionsGame := TScreenOptionsGame.Create;
end;

procedure TScreenOptionsGame.ReloadAllScreens;
begin
  // Reload all screens after language changed
  if (old_Language <> Ini.Language) then
  begin
    UGraphic.UnloadScreens;

    Theme.LoadTheme(Ini.Theme, Ini.Color);
    UGraphic.LoadScreens(USDXVersionStr);

    old_Language := Ini.Language;
    old_SongMenu := Ini.SongMenu;
    old_Sorting  := Ini.Sorting;
    old_Tabs     := Ini.Tabs;
  end;
end;

procedure TScreenOptionsGame.ReloadSongMenu;
begin
  if (Ini.Sorting <> old_Sorting) or (Ini.Tabs <> old_Tabs) or (old_SongMenu <> Ini.SongMenu) then
  begin
    Ini.TabsAtStartup := Ini.Tabs;
    Theme.ThemeSongReload;
    ScreenSong.Free;
    ScreenSong := TScreenSong.Create;
  end;
end;

procedure TScreenOptionsGame.LoadWidgets;
begin
  // when editing this, also update the InteractionID enum declaration
  AddSelectSlide('SING_OPTIONS_GAME_LANGUAGE', Ini.Language, ILanguageTranslated);
  AddSelectSlide('SING_OPTIONS_GAME_SONGMENU', Ini.SongMenu, ISongMenuTranslated);
  AddSelectSlide('SING_OPTIONS_GAME_TABS', Ini.Tabs, ITabsTranslated);
  AddSelectSlide('SING_OPTIONS_GAME_SORTING', Ini.Sorting, ISortingTranslated);
  AddSelectSlide('SING_OPTIONS_GAME_SHOWSCORES', Ini.ShowScores, IShowScoresTranslated);
  AddSelectSlide('SING_OPTIONS_GAME_DEBUG', Ini.Debug, IDebugTranslated);
  UpdateCalculatedSelectSlides(true);
end;

end.
