{$I SCRAPER_DEFINES.INC}

     {********************************************************************
      | This Source Code is subject to the terms of the                  |
      | Mozilla Public License, v. 2.0. If a copy of the MPL was not     |
      | distributed with this file, You can obtain one at                |
      | https://mozilla.org/MPL/2.0/.                                    |
      |                                                                  |
      | Software distributed under the License is distributed on an      |
      | "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or   |
      | implied. See the License for the specific language governing     |
      | rights and limitations under the License.                        |
      ********************************************************************}


      { This sample code uses the SuperObject library for the JSON parsing:
        https://github.com/hgourvest/superobject

        And the TNT Delphi Unicode Controls (compatiable with the last free version)
        to handle a few unicode tasks.

        And optionally, the FastMM/FastCode/FastMove libraries:
        http://sourceforge.net/projects/fastmm/
        }


library theaudiodb;

// To-Do:
// 1. Decide which poster sizes to grab

uses
  FastMM4,
  FastMove,
  FastCode,
  Windows,
  SysUtils,
  Classes,
  Forms,
  Controls,
  DateUtils,
  SyncObjs,
  Dialogs,
  TNTClasses,
  TNTSysUtils,
  SuperObject,
  WinInet,
  theaudiodb_search_unit in 'theaudiodb_search_unit.pas',
  TheAudioDB_MediaNameParsingUnit in 'TheAudioDB_MediaNameParsingUnit.pas',
  TheAudioDB_Misc_Utils_Unit in 'TheAudioDB_Misc_Utils_Unit.pas',
  global_consts in 'global_consts.pas',
  TheAudioDB_configformunit in 'TheAudioDB_configformunit.pas' {ConfigForm};

{$R *.res}

Const
  // Settings Registry Path and Key
  ScraperRegKey    : String = 'Software\VirtuaMedia\ZoomPlayer\Scrapers\TheAudioDB';
  RegKeySecuredStr : String = 'Secured';
  RegKeyMinMediaNameLengthForScrapingByNameStr : String = 'MinMediaNameLengthForScrapingByName';

  //Strings used to store the data in the Metadata File
  mdfPrefix : String = 'theaudiodb_';

  IMAGE_FILE_LARGE_ADDRESS_AWARE = $0020;
  {$SetPEFlags IMAGE_FILE_LARGE_ADDRESS_AWARE}


Var
  SecureHTTP                          : Boolean = False;
  MinMediaNameLengthForScrapingByName : Integer = 2;


// Called by Zoom Player to free any resources allocated in the DLL prior to unloading the DLL.
Procedure FreeScraper; stdcall;
var
  I : Integer;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT('c:\log\.ScrapeTheAudioDBInit.txt','Free Scraper (before)');{$ENDIF}
  csQuery.Enter;
  Try
    {$IFDEF LOCALTRACE}DebugMsgFT('c:\log\.ScrapeTheMovieDBInit.txt','csQuery.Enter');{$ENDIF}
    If QueryTSList <> nil then
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT('c:\log\.ScrapeTheMovieDBInit.txt','QueryTSList <> nil');{$ENDIF}
      For I := 0 to QueryTSList.Count-1 do Dispose(PInt64(QueryTSList[I]));
      FreeAndNil(QueryTSList);
    End;
  Finally
    csQuery.Leave;
    {$IFDEF LOCALTRACE}DebugMsgFT('c:\log\.ScrapeTheMovieDBInit.txt','csQuery.Leave');{$ENDIF}
  End;
  csQuery.Free;
  {$IFDEF LOCALTRACE}
  DebugMsgFT('c:\log\.ScrapeTheAudioDBInit.txt','Free Scraper (after)');
  csDebug.Free;
  {$ENDIF}
  csParser.Free;
end;


// Called by Zoom Player to init any resources.
function InitScraper : Boolean; stdcall;
begin
  {$IFDEF LOCALTRACE}
  csDebug := TCriticalSection.Create;
  QueryPerformanceFrequency(qTimer64Freq);
  QueryPerformanceCounter(DebugStartTime);
  DebugMsgFT('c:\log\.ScrapeTheAudioDBInit.txt','Init Scraper (before)');
  {$ENDIF}
  if not Assigned(csQuery) then
    csQuery := TCriticalSection.Create;
  if not Assigned(QueryTSList) then
    QueryTSList := TList.Create;

  csParser := TCriticalSection.Create;
  Result := True;
  {$IFDEF LOCALTRACE}DebugMsgFT('c:\log\.ScrapeTheAudioDBInit.txt','Init Scraper (after)');{$ENDIF}
end;


// Called by Zoom Player to verify if a configuration dialog is available.
// Return True if a dialog exits and False if no configuration dialog exists.
function CanConfigure : Boolean; stdcall;
begin
  Result := True;
end;


// Called by Zoom Player to show the scraper's configuration dialog.
Procedure Configure(CenterOnWindow : HWND); stdcall;
var
  CenterOnRect : TRect;
  tmpInt       : Integer;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT('c:\log\.ScrapeTheAudioDBInit.txt','Configuration (before)');{$ENDIF}
  If GetWindowRect(CenterOnWindow,CenterOnRect) = False then
    GetWindowRect(0,CenterOnRect); // Can't find window, center on screen

  ConfigForm := TConfigForm.Create(nil);
  ConfigForm.SetBounds(CenterOnRect.Left+(((CenterOnRect.Right -CenterOnRect.Left)-ConfigForm.Width)  div 2),
                       CenterOnRect.Top +(((CenterOnRect.Bottom-CenterOnRect.Top )-ConfigForm.Height) div 2),ConfigForm.Width,ConfigForm.Height);

  ConfigForm.SecureCommCB.Checked := SecureHTTP;
  ConfigForm.edtMinMediaNameLengthForScrapingByName.Text := IntToStr(MinMediaNameLengthForScrapingByName);

  If ConfigForm.ShowModal = mrOK then
  Begin
    // Save to registry
    If SecureHTTP <> ConfigForm.SecureCommCB.Checked then
    Begin
      SecureHTTP := ConfigForm.SecureCommCB.Checked;
      SetRegDWord(HKEY_CURRENT_USER,ScraperRegKey,RegKeySecuredStr,Integer(SecureHTTP));
    End;
    tmpInt := StrToInt(ConfigForm.edtMinMediaNameLengthForScrapingByName.Text);
    If MinMediaNameLengthForScrapingByName <> tmpInt then
    Begin
      MinMediaNameLengthForScrapingByName := tmpInt;
      SetRegDWord(HKEY_CURRENT_USER,ScraperRegKey,RegKeyMinMediaNameLengthForScrapingByNameStr,MinMediaNameLengthForScrapingByName);
    End;
  End;
  ConfigForm.Free;
  {$IFDEF LOCALTRACE}DebugMsgFT('c:\log\.ScrapeTheAudioDBInit.txt','Configuration (after)');{$ENDIF}
end;


Const
// Current results may be:
  SCRAPE_RESULT_SUCCESS = NO_ERROR; // = 0 - Scraping successful

  SCRAPE_RESULT_NOT_FOUND = -1; // Failed to scrape (no results found)
  // other negative values defined in theaudiodb_Search_Unit.pas like SCRAPE_RESULT_ERROR_DB_UNAUTHORIZED

  SCRAPE_RESULT_ERROR_INTERNET = INTERNET_ERROR_BASE; // = 12000 - Online Database connection error

  SCRAPE_RESULT_ERROR_OTHER = MaxInt; // Other error


Function ScrapeDB(pcMediaName, pcDataPath, pcPosterFile, pcBackdropFile, pcStillFile, pcDataFile : PChar; IsFolder : Boolean; CategoryType : Integer; PreferredLanguage : PChar; grabThreadID : Integer) : Integer; stdcall;
var
  LastErrorCode         : Integer;
  AlbumMetaData         : PtadbAlbumMetaDataRecord;
  TrackMetaData         : PtadbTrackMetaDataRecord;
  mdAlbumName           : WideString;
  mdArtistName          : WideString;

  Media_Name            : WideString;
  Media_Path            : WideString;
  Poster_File           : WideString;
  Data_Path             : WideString;
  Data_File             : WideString;

  sDownloadStatus       : String;
  mdList                : TTNTStringList;
  Hash1                 : Int64;
  Hash2                 : Int64;

  sAnsi                 : AnsiString;

  {
  sSecure               : String;
  sParsed               : WideString;
  Backdrop_File         : WideString;
  Still_File            : WideString;
  IMDB_ID               : Integer;
  mdMediaNameYear       : Integer;
  mdMediaNameMonth      : Integer;
  mdMediaNameDay        : Integer;
  mdMediaNameSeason     : Integer;
  mdMediaNameEpisode    : Integer;
  mdMediaNameRes        : String;
  sList                 : TStringList;
  SkipSearchForTVShowID : Boolean;
  tmpTVShowBackdropPath : String;
  tmpTVShowGenre        : WideString;

  sDLStatusBackdrop     : String;
  ErrCodeBackdrop       : Integer;
  dlBackdropComplete    : Boolean;
  dlBackdropSuccess     : Boolean;
  dlBackdropSearch      : Boolean;

  sDLStatusStillImage   : String;
  ErrCodeStillImage     : Integer;
  dlStillImageComplete  : Boolean;
  dlStillImageSuccess   : Boolean;
  dlStillImageSearch    : Boolean;

  sDLStatusPoster       : String;
  ErrCodePoster         : Integer;
  dlPosterComplete      : Boolean;
  dlPosterSuccess       : Boolean;
  dlPosterSearch        : Boolean;}

begin
  // [pcMediaName]
  // Contains the UTF8 encoded media file name being scrapped.
  //
  //
  // [pcDataPath]
  // Contains the UTF8 encoded folder name used to save the meta-data
  // file and any scraped media (images for example).
  //
  //
  // [pcPosterFile, pcBackdropFile, pcStillFile]
  // Contains the UTF8 encoded file name to use when saving a scraped images.
  //
  //
  // [pcDataFile]
  // The file name to create and write the scrapped meta-data.
  // Make sure to use the full path [DataPath]+[DataFile]
  // If the value is empty, do not save a data file!
  //
  //
  // [IsFolder]
  // Indicates if "pcMediaName" is a folder or a media file.
  //
  //
  // [CategoryType]
  // Indicates the type of content being passed, possible values are:
  // 0 = Unknown (can be anything)
  // 1 = Movies
  // 2 = TV Shows
  // 3 = Sporting Events
  // 4 = Music
  // The CategoryType parameter can be used to help determine how to
  // better parse the MediaName parameter and how to query the online database.
  //
  //
  // [grabThreadID]
  // Indicates which thread number is currently scraping (useful for debugging).
  //
  //
  // Note:
  // All Meta-Data entries should use a simple VALUE=DATA format,
  // Only one line per entry, for example:
  // TITLE=An interesting movie
  //
  // When multiple lines are required, use the "\n" tag to signify a
  // line break, for example:
  // Overview=Line 1\nLine2\nLine3
  //
  // The exported meta-data text file should be unicode (NOT UTF8) encoded.
  //
  // You can add meta-data entries that Zoom Player does not currently
  // support, Zoom Player will ignore unknown entries. Support for unknown
  // meta-data entries may be integrated into Zoom Player in a new
  // version later on.
  //
  // Try validating your code to ensure there are no stalling points,
  // returning a value as soon as possible is required for smooth
  // operation.
  //
  // Return either true or false to indicate scraping success/failure.
  // Do not create a data file on failure.



  // Here is sample code to grab meta-data from theaudiodb.org,
  // to prevent conflicts, The API key is not included, you can
  // sign up for your own key through theaudiodb.org web site.

  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Enter CriticlSection');{$ENDIF}
  csParser.Enter;
  Try


  Result        := SCRAPE_RESULT_NOT_FOUND;
  LastErrorCode := 0;

  sAnsi       := pcMediaName;
  Media_Name  := UTF8Decode(ExtractFileName(sAnsi));
  Media_Path  := UTF8Decode(ExtractFilePath(sAnsi));
  Data_File   := UTF8Decode(String(pcDatafile));
  Data_Path   := UTF8Decode(String(pcDataPath));
  Poster_File := UTF8Decode(String(pcPosterFile));
  {$IFDEF LOCALTRACE}
  DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Media_Name  : '+Media_Name);
  DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Media_Path  : '+Media_Path);
  DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Data_File   : '+Data_File);
  DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Data_Path   : '+Data_Path);
  DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Poster_File : '+Poster_File);
  {$ENDIF}

  If (Media_Name <> '') and (Data_Path <> '') and (Data_File <> '') then
  Begin
    // Set HTTP secured if enabled
    //If SecureHTTP = True then sSecure := 's' else sSecure := '';

    If IsFolder = True then
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Processing folder');{$ENDIF}
      New(AlbumMetaData);
      ParseFolderNameForAlbumAndArtist(Media_Name,mdArtistName,mdAlbumName);

      If mdAlbumName <> '' then
      Begin
        {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Album name found');{$ENDIF}
        LastErrorCode := SearchTheAudioDB_Album(mdArtistName,mdAlbumName,SecureHTTP,AlbumMetaData{$IFDEF LOCALTRACE},grabThreadID{$ENDIF});
        If LastErrorCode = S_OK then
        Begin
          {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'SearchTheMovieDB_Album Success');{$ENDIF}
          Result := S_OK;
          If (AlbumMetaData^.tadb_strAlbumThumb <> '') and (Poster_File <> '') then
          Begin
           {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Download Thumbnail : '+AlbumMetaData^.tadb_strAlbumThumb);{$ENDIF}
           If DownloadImageToFile(AlbumMetaData^.tadb_strAlbumThumb,Data_Path,Poster_File,sDownloadStatus,LastErrorCode,tadbQueryInternetTimeout{$IFDEF LOCALTRACE},grabThreadID{$ENDIF}) = True then
           Begin
             {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Download Complete');{$ENDIF}
           End
           {$IFDEF LOCALTRACE}Else DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Download Error #'+IntToHex(LastErrorCode,8)+', http status: '+sDownloadStatus){$ENDIF};
          End;
        End
        {$IFDEF LOCALTRACE}Else DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Search Error #'+IntToHex(LastErrorCode,8)){$ENDIF};
      End
      {$IFDEF LOCALTRACE}Else DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Unable to identify Album name from '+pcMediaName){$ENDIF};

      // Save Album Meta Data
      If (Result = S_OK) then
      Begin
        mdList := TTNTStringList.Create;

        With AlbumMetaData^ do
        Begin
          // [MetaEntry1]  :  // Displayed in the meta-data's Title area
          // [MetaEntry2]  :  // Displayed in the meta-data's Date area
          // [MetaEntry3]  :  // Displayed in the meta-data's Duration
          // [MetaEntry4]  :  // Displayed in the meta-data's Genre/Type area
          // [MetaEntry5]  :  // Displayed in the meta-data's Overview/Description area
          // [MetaEntry6]  :  // Displayed in the meta-data's Actors/Media info area
          // [MetaRating]  :  // Meta rating, value of 0-100, 0=disabled

          If tadb_strAlbum               <> '' then mdList.Add('MetaEntry1='+tadb_strAlbum);
          If tadb_intYearReleased        <> -1 then mdList.Add('MetaEntry2='+IntToStr(tadb_intYearReleased));
          If tadb_strArtist              <> '' then mdList.Add('MetaEntry4='+tadb_strArtist);
          If tadb_strDescriptionEN       <> '' then mdList.Add('MetaEntry5='+tadb_strDescriptionEN);
          If tadb_strGenre               <> '' then mdList.Add('MetaEntry6='+tadb_strGenre);
          If tadb_intScore               <> -1 then mdList.Add('MetaRating='+IntToStr(tadb_intScore));

          //If tadb_strArtist              <> '' then mdList.Add('Artist='+tadb_strArtist);

          // ZP doesn't really use these:
          //If tadb_idAlbum                <> -1 then mdList.Add('tadbAlbumID='+IntToStr(tadb_idAlbum));
          //If tadb_idArtist               <> -1 then mdList.Add('tadbArtistID='+IntToStr(tadb_idArtist));
          //If tadb_idLabel                <> -1 then mdList.Add('tadbLabelID='+IntToStr(tadb_idLabel));
          //If tadb_strLabel               <> '' then mdList.Add('Label='+tadb_strLabel);
          //If tadb_strReleaseFormat       <> '' then mdList.Add('ReleaseFormat='+tadb_strReleaseFormat);
          //If tadb_intSales               <> -1 then mdList.Add('Sales='+IntToStr(tadb_intSales));
          //If tadb_strAlbumThumb          <> '' then mdList.Add('AlbumThumb='+tadb_strAlbumThumb);
          //If tadb_strAlbumThumbBack      <> '' then mdList.Add('AlbumThumbBack='+tadb_strAlbumThumbBack);
          //If tadb_strAlbumCDart          <> '' then mdList.Add('AlbumCDart='+tadb_strAlbumCDart);
          //If tadb_strAlbumSpine          <> '' then mdList.Add('AlbumSpine='+tadb_strAlbumSpine);
          //If tadb_intLoved               <> -1 then mdList.Add('Loved='+IntToStr(tadb_intLoved));
          //If tadb_intScoreVotes          <> -1 then mdList.Add('ScoreVotes='+IntToStr(tadb_intScoreVotes));
          //If tadb_strReview              <> '' then mdList.Add('Review='+tadb_strReview);
          //If tadb_strMood                <> '' then mdList.Add('Mood='+tadb_strMood);
          //If tadb_strTheme               <> '' then mdList.Add('Theme='+tadb_strTheme);
          //If tadb_strSpeed               <> '' then mdList.Add('Speed='+tadb_strSpeed);
          //If tadb_strLocation            <> '' then mdList.Add('Location='+tadb_strLocation);
          //If tadb_strMusicBrainzID       <> '' then mdList.Add('MusicBrainzID='+tadb_strMusicBrainzID);
          //If tadb_strMusicBrainzArtistID <> '' then mdList.Add('MusicBrainzArtistID='+tadb_strMusicBrainzArtistID);
          //If tadb_strItunesID            <> '' then mdList.Add('ItunesID='+tadb_strItunesID);
          //If tadb_strAmazonID            <> '' then mdList.Add('AmazonID='+tadb_strAmazonID);
          //If tadb_strLocked              <> '' then mdList.Add('Locked='+tadb_strLocked);
        End;

        If mdList.Count > 0 then
        Begin
          If WideDirectoryExists(Data_Path) = False then WideForceDirectories(Data_Path);
          Try
            mdList.SaveToFile(Data_Path+Data_File);
          Except
            {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Exception saving meta-data file "'+Data_Path+Data_File+'"');{$ENDIF}
          End;
        End;
        mdList.Free;
      End;

      Dispose(AlbumMetaData);
    End
      else
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Processing file');{$ENDIF}
      CalcGabestHash(Media_Path+Media_Name,Hash1,Hash2);
      If (Hash1 <> 0) and (Hash2 <> 0) then
      Begin
        New(TrackMetaData);
        LastErrorCode := SearchTheAudioDB_FileHash(Hash1,Hash2,SecureHTTP,TrackMetaData{$IFDEF LOCALTRACE},grabThreadID{$ENDIF});
        If LastErrorCode = S_OK then
        Begin
          Result := S_OK;
          If (TrackMetaData^.tadb_strTrackThumb <> '') and (Poster_File <> '') then
          Begin
           {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Download Thumbnail : '+TrackMetaData^.tadb_strTrackThumb);{$ENDIF}
           If DownloadImageToFile(TrackMetaData^.tadb_strTrackThumb,Data_Path,Poster_File,sDownloadStatus,LastErrorCode,tadbQueryInternetTimeout{$IFDEF LOCALTRACE},grabThreadID{$ENDIF}) = True then
           Begin
             {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Download Complete');{$ENDIF}
           End
           {$IFDEF LOCALTRACE}Else DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Download Error #'+IntToHex(LastErrorCode,8)+', http status: '+sDownloadStatus){$ENDIF};
          End;
        End;

        // Save Track Meta Data
        If (Result = S_OK) then
        Begin
          mdList := TTNTStringList.Create;

          With TrackMetaData^ do
          Begin
            // [MetaEntry1]  :  // Displayed in the meta-data's Title area
            // [MetaEntry2]  :  // Displayed in the meta-data's Date area
            // [MetaEntry3]  :  // Displayed in the meta-data's Duration
            // [MetaEntry4]  :  // Displayed in the meta-data's Genre/Type area
            // [MetaEntry5]  :  // Displayed in the meta-data's Overview/Description area
            // [MetaEntry6]  :  // Displayed in the meta-data's Actors/Media info area
            // [MetaRating]  :  // Meta rating, value of 0-100, 0=disabled

            If tadb_strTrack         <> '' then mdList.Add('MetaEntry1='+tadb_strTrack);
            If tadb_intTrackNumber    > -1 then mdList.Add('MetaEntry2='+'Track '+IntToStr(tadb_intTrackNumber));
            If tadb_intDuration       > -1 then mdList.Add('MetaEntry3='+EncodeDuration(tadb_intDuration div 1000));

            If tadb_strAlbum         <> '' then mdList.Add('MetaEntry4='+tadb_strAlbum);
            If tadb_strDescriptionEN <> '' then mdList.Add('MetaEntry5='+tadb_strDescriptionEN);
            If tadb_strGenre         <> '' then mdList.Add('MetaEntry6='+tadb_strGenre);
            If tadb_intScore          > -1 then mdList.Add('MetaRating='+IntToStr(tadb_intScore));
            //If tadb_strTrackLyrics   <> '' then mdList.Add('MetaEntry6='+tadb_strTrackLyrics);
          End;

          If mdList.Count > 0 then
          Begin
            If WideDirectoryExists(Data_Path) = False then WideForceDirectories(Data_Path);
            Try
              mdList.SaveToFile(Data_Path+Data_File);
            Except
              {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Exception saving meta-data file "'+Data_Path+Data_File+'"');{$ENDIF}
            End;
          End;
          mdList.Free;
        End;
        Dispose(TrackMetaData);
      End;
    End;
  End;

  If LastErrorCode <> 0 then
  Begin
    // System Error Codes - https://msdn.microsoft.com/en-us/library/windows/desktop/ms681381%28v=vs.85%29.aspx
    If (LastErrorCode >= INTERNET_ERROR_BASE) and (LastErrorCode <= 12175) then  // ERROR_INTERNET_* from WinInet
    Begin
      Result := SCRAPE_RESULT_ERROR_INTERNET
    End
      else
    Begin
      If LastErrorCode > 0 then
        Result := SCRAPE_RESULT_ERROR_OTHER else
        Result := LastErrorCode;
    End;
  End;

  Finally
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Leave CriticlSection (before)');{$ENDIF}
    csParser.Leave;
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'Leave CriticlSection (after)');{$ENDIF}
  End;

  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(grabThreadID)+scrapeLogExt,'ScrapeDB End (Result: '+IntToStr(Result)+'; LastErrorCode: '+IntToStr(LastErrorCode)+')'+CRLF+CRLF);{$ENDIF}
end;


exports
   InitScraper,
   FreeScraper,
   CanConfigure,
   ScrapeDB,
   Configure;


begin
  // Required to notify the memory manager that this DLL is being called from a multi-threaded application!
  IsMultiThread := True;
end.

