{$I SCRAPER_DEFINES.INC}

unit TheAudioDB_MediaNameParsingUnit;


interface


procedure ParseFolderNameForAlbumAndArtist(FolderName : WideString; var ArtistName, AlbumName : WideString);


implementation

uses sysutils, tntsysutils, dateutils, tntclasses, TheAudioDB_misc_utils_unit, global_consts;


procedure ParseFolderNameForAlbumAndArtist(FolderName : WideString; var ArtistName, AlbumName : WideString);
var
  iPos : Integer;
begin
  ArtistName := '';
  AlbumName  := '';

  iPos := Pos('-',FolderName);

  If iPos > 0 then
  Begin
    ArtistName := Trim(Copy(FolderName,1,iPos-1));
    AlbumName  := Trim(Copy(FolderName,iPos+1,Length(FolderName)-iPos));
  End
    else
  Begin
    AlbumName := Trim(FolderName);
  End;
end;


procedure Split(S : WideString; Ch : Char; sList : TTNTStrings);
var
  I : Integer;
begin
  While Pos(Ch,S) > 0 do
  Begin
    I := Pos(Ch,S);
    sList.Add(Copy(S,1,I-1));
    Delete(S,1,I);
  End;
  If Length(S) > 0 then sList.Add(S);
end;


procedure Combine(sList : TTNTStrings; Ch : Char; var S : WideString);
var
  I : Integer;
begin
  S := '';
  For I := 0 to sList.Count-1 do
  Begin
    If I < sList.Count-1 then S := S+sList[I]+Ch else S := S+sList[I];
  End;
end;


Function ExtractFileNameNoExt(FileName : String) : String;
var
  I : Integer;
begin
  If Length(FileName) > 0 then
  Begin
    Result := ExtractFileName(FileName);
    For I := Length(Result) downto 1 do If Result[I] = '.' then
    Begin
      If I > 1 then Result := Copy(Result,1,I-1);
      Break;
    End;
  End
  Else Result := '';
end;


end.

