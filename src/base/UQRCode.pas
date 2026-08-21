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
 * Minimal QR code generator, just enough to show the address of the song
 * request server on screen.
 *
 * Only what is needed for that is implemented: byte mode, error correction
 * level L and versions 1 to 5, which all use a single error correction block
 * and hold up to 108 characters.
 *}
unit UQRCode;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  Math,
  SysUtils;

const
  QR_MAX_VERSION = 5;
  QR_MAX_LENGTH  = 106; // capacity of version 5 minus the byte mode header

type
  {* Square module matrix, Dark[Y * Size + X] tells whether a module is dark.
     The quiet zone around the symbol is not part of it. *}
  TQRCode = record
    Size: integer;
    Dark: array of boolean;
  end;

{**
 * Encodes Text as a QR code. Returns false if the text is empty or too long
 * for the supported versions.
 *}
function QREncode(const Text: RawByteString; out Code: TQRCode): boolean;

implementation

type
  TByteArray = array of byte;

const
  // error correction level L: one block per version, versions 1 to 5
  TotalCodewords: array[1..QR_MAX_VERSION] of integer = (26, 44, 70, 100, 134);
  ECCodewords:    array[1..QR_MAX_VERSION] of integer = (7, 10, 15, 20, 26);
  // 2 bit format field of error correction level L
  ECFormatBits = 1;

{ Galois field GF(2^8) arithmetic with the QR primitive polynomial }

function GFMultiply(X, Y: byte): byte;
var
  Z, I: integer;
begin
  Z := 0;
  for I := 7 downto 0 do
  begin
    Z := (Z shl 1) xor ((Z shr 7) * $11D);
    Z := Z xor (((Y shr I) and 1) * X);
  end;

  Result := Z and $FF;
end;

{* Reed-Solomon generator polynomial of the given degree. *}
function RSDivisor(Degree: integer): TByteArray;
var
  I, J, Root: integer;
begin
  SetLength(Result, Degree);
  FillChar(Result[0], Degree, 0);
  Result[Degree - 1] := 1;

  Root := 1;
  for I := 0 to Degree - 1 do
  begin
    for J := 0 to Degree - 1 do
    begin
      Result[J] := GFMultiply(Result[J], byte(Root));
      if (J + 1 < Degree) then
        Result[J] := Result[J] xor Result[J + 1];
    end;
    Root := GFMultiply(byte(Root), 2);
  end;
end;

{* Error correction codewords for the given data. *}
function RSRemainder(const Data, Divisor: TByteArray): TByteArray;
var
  I, J: integer;
  Factor: byte;
begin
  SetLength(Result, Length(Divisor));
  FillChar(Result[0], Length(Divisor), 0);

  for I := 0 to High(Data) do
  begin
    Factor := Data[I] xor Result[0];

    for J := 0 to High(Result) - 1 do
      Result[J] := Result[J + 1];
    Result[High(Result)] := 0;

    for J := 0 to High(Result) do
      Result[J] := Result[J] xor GFMultiply(Divisor[J], Factor);
  end;
end;

{ symbol construction }

type
  TQRBuilder = class
    private
      Size:    integer;
      Modules: array of boolean;
      IsFunc:  array of boolean;

      procedure SetFunctionModule(X, Y: integer; Dark: boolean);
      function  GetModule(X, Y: integer): boolean;
      procedure DrawFinderPattern(X, Y: integer);
      procedure DrawAlignmentPattern(X, Y: integer);
      procedure DrawFormatBits(Mask: integer);
      procedure DrawFunctionPatterns(Version: integer);
      procedure DrawCodewords(const Data: TByteArray);
      procedure ApplyMask(Mask: integer);
      function  CountRunPenalty(Run: integer): integer;
      function  PenaltyScore: integer;
    public
      constructor Create(Version: integer);
      procedure Build(const Data: TByteArray);
      procedure CopyTo(out Code: TQRCode);
  end;

constructor TQRBuilder.Create(Version: integer);
begin
  inherited Create;

  Size := Version * 4 + 17;
  SetLength(Modules, Size * Size);
  SetLength(IsFunc, Size * Size);
end;

function TQRBuilder.GetModule(X, Y: integer): boolean;
begin
  Result := (X >= 0) and (X < Size) and (Y >= 0) and (Y < Size) and Modules[Y * Size + X];
end;

procedure TQRBuilder.SetFunctionModule(X, Y: integer; Dark: boolean);
begin
  if (X < 0) or (X >= Size) or (Y < 0) or (Y >= Size) then
    Exit;

  Modules[Y * Size + X] := Dark;
  IsFunc[Y * Size + X]  := true;
end;

procedure TQRBuilder.DrawFinderPattern(X, Y: integer);
var
  DX, DY, Dist: integer;
begin
  for DY := -4 to 4 do
    for DX := -4 to 4 do
    begin
      Dist := Max(Abs(DX), Abs(DY));
      SetFunctionModule(X + DX, Y + DY, (Dist <> 2) and (Dist <> 4));
    end;
end;

procedure TQRBuilder.DrawAlignmentPattern(X, Y: integer);
var
  DX, DY: integer;
begin
  for DY := -2 to 2 do
    for DX := -2 to 2 do
      SetFunctionModule(X + DX, Y + DY, Max(Abs(DX), Abs(DY)) <> 1);
end;

procedure TQRBuilder.DrawFormatBits(Mask: integer);
var
  Data, Rem, Bits, I: integer;
begin
  Data := (ECFormatBits shl 3) or Mask;

  // BCH(15, 5) error correction of the format field
  Rem := Data;
  for I := 0 to 9 do
    Rem := (Rem shl 1) xor ((Rem shr 9) * $537);

  Bits := ((Data shl 10) or Rem) xor $5412;

  // first copy, around the top left finder pattern
  for I := 0 to 5 do
    SetFunctionModule(8, I, ((Bits shr I) and 1) <> 0);
  SetFunctionModule(8, 7, ((Bits shr 6) and 1) <> 0);
  SetFunctionModule(8, 8, ((Bits shr 7) and 1) <> 0);
  SetFunctionModule(7, 8, ((Bits shr 8) and 1) <> 0);
  for I := 9 to 14 do
    SetFunctionModule(14 - I, 8, ((Bits shr I) and 1) <> 0);

  // second copy, split between the other two finder patterns
  for I := 0 to 7 do
    SetFunctionModule(Size - 1 - I, 8, ((Bits shr I) and 1) <> 0);
  for I := 8 to 14 do
    SetFunctionModule(8, Size - 15 + I, ((Bits shr I) and 1) <> 0);

  // module that is always dark
  SetFunctionModule(8, Size - 8, true);
end;

procedure TQRBuilder.DrawFunctionPatterns(Version: integer);
var
  I: integer;
begin
  // timing patterns
  for I := 0 to Size - 1 do
  begin
    SetFunctionModule(6, I, (I mod 2) = 0);
    SetFunctionModule(I, 6, (I mod 2) = 0);
  end;

  // finder patterns including their separators
  DrawFinderPattern(3, 3);
  DrawFinderPattern(Size - 4, 3);
  DrawFinderPattern(3, Size - 4);

  // versions 2 to 6 have a single alignment pattern
  if (Version >= 2) then
    DrawAlignmentPattern(Size - 7, Size - 7);

  // reserve the format areas, the final mask is drawn later
  DrawFormatBits(0);
end;

procedure TQRBuilder.DrawCodewords(const Data: TByteArray);
var
  Right, Vert, J, X, Y, BitIndex, TotalBits: integer;
  Upward: boolean;
begin
  BitIndex  := 0;
  TotalBits := Length(Data) * 8;

  Right := Size - 1;
  while (Right >= 1) do
  begin
    // the vertical timing pattern is not part of the data area
    if (Right = 6) then
      Right := 5;

    Upward := ((Right + 1) and 2) = 0;

    for Vert := 0 to Size - 1 do
    begin
      for J := 0 to 1 do
      begin
        X := Right - J;
        if Upward then
          Y := Size - 1 - Vert
        else
          Y := Vert;

        if (not IsFunc[Y * Size + X]) and (BitIndex < TotalBits) then
        begin
          Modules[Y * Size + X] :=
            ((Data[BitIndex shr 3] shr (7 - (BitIndex and 7))) and 1) <> 0;
          Inc(BitIndex);
        end;
      end;
    end;

    Dec(Right, 2);
  end;
end;

procedure TQRBuilder.ApplyMask(Mask: integer);
var
  X, Y: integer;
  Invert: boolean;
begin
  for Y := 0 to Size - 1 do
    for X := 0 to Size - 1 do
    begin
      if IsFunc[Y * Size + X] then
        Continue;

      case Mask of
        0: Invert := ((X + Y) mod 2) = 0;
        1: Invert := (Y mod 2) = 0;
        2: Invert := (X mod 3) = 0;
        3: Invert := ((X + Y) mod 3) = 0;
        4: Invert := (((X div 3) + (Y div 2)) mod 2) = 0;
        5: Invert := ((X * Y) mod 2) + ((X * Y) mod 3) = 0;
        6: Invert := ((((X * Y) mod 2) + ((X * Y) mod 3)) mod 2) = 0;
        7: Invert := ((((X + Y) mod 2) + ((X * Y) mod 3)) mod 2) = 0;
        else
          Invert := false;
      end;

      if Invert then
        Modules[Y * Size + X] := not Modules[Y * Size + X];
    end;
end;

function TQRBuilder.CountRunPenalty(Run: integer): integer;
begin
  if (Run >= 5) then
    Result := 3 + (Run - 5)
  else
    Result := 0;
end;

{**
 * Penalty score of the current matrix, used to pick the mask that gives the
 * most readable symbol (rules 1 to 4 of the specification).
 *}
function TQRBuilder.PenaltyScore: integer;
var
  X, Y, Run, Dark, Total, K, Deviation: integer;
  Color: boolean;
  Line: array of boolean;

  function MatchesFinderPattern(const Bits: array of boolean; Start: integer): boolean;
  const
    // 1011101 with four light modules on one of its sides
    Pattern: array[0..10] of boolean =
      (true, false, true, true, true, false, true, false, false, false, false);
  var
    I: integer;
    Forward_, Backward: boolean;
  begin
    Forward_  := true;
    Backward := true;

    for I := 0 to 10 do
    begin
      if (Bits[Start + I] <> Pattern[I]) then
        Forward_ := false;
      if (Bits[Start + I] <> Pattern[10 - I]) then
        Backward := false;
    end;

    Result := Forward_ or Backward;
  end;

begin
  Result := 0;
  SetLength(Line, Size);

  // rule 1: runs of five or more modules of the same colour
  // rule 3: patterns that look like a finder pattern
  for Y := 0 to Size - 1 do
  begin
    for X := 0 to Size - 1 do
      Line[X] := GetModule(X, Y);

    Run := 1;
    Color := Line[0];
    for X := 1 to Size - 1 do
    begin
      if (Line[X] = Color) then
        Inc(Run)
      else
      begin
        Result := Result + CountRunPenalty(Run);
        Color := Line[X];
        Run := 1;
      end;
    end;
    Result := Result + CountRunPenalty(Run);

    for X := 0 to Size - 11 do
      if MatchesFinderPattern(Line, X) then
        Result := Result + 40;
  end;

  for X := 0 to Size - 1 do
  begin
    for Y := 0 to Size - 1 do
      Line[Y] := GetModule(X, Y);

    Run := 1;
    Color := Line[0];
    for Y := 1 to Size - 1 do
    begin
      if (Line[Y] = Color) then
        Inc(Run)
      else
      begin
        Result := Result + CountRunPenalty(Run);
        Color := Line[Y];
        Run := 1;
      end;
    end;
    Result := Result + CountRunPenalty(Run);

    for Y := 0 to Size - 11 do
      if MatchesFinderPattern(Line, Y) then
        Result := Result + 40;
  end;

  // rule 2: blocks of 2x2 modules of the same colour
  for Y := 0 to Size - 2 do
    for X := 0 to Size - 2 do
    begin
      Color := GetModule(X, Y);
      if (Color = GetModule(X + 1, Y)) and
         (Color = GetModule(X, Y + 1)) and
         (Color = GetModule(X + 1, Y + 1)) then
        Result := Result + 3;
    end;

  // rule 4: deviation from an even distribution of dark modules
  Dark := 0;
  Total := Size * Size;
  for Y := 0 to Size - 1 do
    for X := 0 to Size - 1 do
      if GetModule(X, Y) then
        Inc(Dark);

  // abs(percentage of dark modules - 50) divided by 5, rounded down
  Deviation := Abs(Dark * 20 - Total * 10); // abs(dark / total - 0.5) * total * 20
  K := Deviation div Total;
  Result := Result + K * 10;
end;

procedure TQRBuilder.Build(const Data: TByteArray);
var
  Mask, BestMask, Score, BestScore: integer;
begin
  DrawCodewords(Data);

  BestMask := 0;
  BestScore := High(integer);

  for Mask := 0 to 7 do
  begin
    ApplyMask(Mask);
    DrawFormatBits(Mask);

    Score := PenaltyScore;
    if (Score < BestScore) then
    begin
      BestScore := Score;
      BestMask := Mask;
    end;

    // undo, applying the same mask twice restores the matrix
    ApplyMask(Mask);
  end;

  ApplyMask(BestMask);
  DrawFormatBits(BestMask);
end;

procedure TQRBuilder.CopyTo(out Code: TQRCode);
var
  I: integer;
begin
  Code.Size := Size;
  SetLength(Code.Dark, Size * Size);
  for I := 0 to High(Modules) do
    Code.Dark[I] := Modules[I];
end;

function QREncode(const Text: RawByteString; out Code: TQRCode): boolean;
var
  Version, DataLen, NeededBits, I, BitPos: integer;
  Data, ECC, Full: TByteArray;
  Builder: TQRBuilder;

  procedure AppendBits(Value, Count: integer);
  var
    J: integer;
  begin
    for J := Count - 1 downto 0 do
    begin
      if (((Value shr J) and 1) <> 0) then
        Data[BitPos shr 3] := Data[BitPos shr 3] or (1 shl (7 - (BitPos and 7)));
      Inc(BitPos);
    end;
  end;

begin
  Result := false;
  Code.Size := 0;
  SetLength(Code.Dark, 0);

  DataLen := Length(Text);
  if (DataLen = 0) or (DataLen > QR_MAX_LENGTH) then
    Exit;

  // 4 bits mode indicator + 8 bits character count + the text itself
  NeededBits := 4 + 8 + DataLen * 8;

  Version := 0;
  for I := 1 to QR_MAX_VERSION do
    if (NeededBits <= (TotalCodewords[I] - ECCodewords[I]) * 8) then
    begin
      Version := I;
      Break;
    end;

  if (Version = 0) then
    Exit;

  // data codewords: header, text, terminator and padding
  SetLength(Data, TotalCodewords[Version] - ECCodewords[Version]);
  FillChar(Data[0], Length(Data), 0);

  BitPos := 0;
  AppendBits($4, 4);        // byte mode
  AppendBits(DataLen, 8);
  for I := 1 to DataLen do
    AppendBits(Ord(Text[I]), 8);

  // terminator, as far as it still fits
  I := Length(Data) * 8 - BitPos;
  if (I > 4) then
    I := 4;
  AppendBits(0, I);

  // pad to a full codeword, then alternating padding codewords
  while ((BitPos mod 8) <> 0) do
    AppendBits(0, 1);

  I := 0;
  while (BitPos < Length(Data) * 8) do
  begin
    if ((I mod 2) = 0) then
      AppendBits($EC, 8)
    else
      AppendBits($11, 8);
    Inc(I);
  end;

  // error correction, a single block for all supported versions
  ECC := RSRemainder(Data, RSDivisor(ECCodewords[Version]));

  SetLength(Full, Length(Data) + Length(ECC));
  for I := 0 to High(Data) do
    Full[I] := Data[I];
  for I := 0 to High(ECC) do
    Full[Length(Data) + I] := ECC[I];

  Builder := TQRBuilder.Create(Version);
  try
    Builder.DrawFunctionPatterns(Version);
    Builder.Build(Full);
    Builder.CopyTo(Code);
  finally
    Builder.Free;
  end;

  Result := true;
end;

end.
