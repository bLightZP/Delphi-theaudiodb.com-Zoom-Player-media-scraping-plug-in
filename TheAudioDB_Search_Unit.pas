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
        to handle a few unicode tasks. }


unit theaudiodb_search_unit;

interface

uses
  Classes,
  SyncObjs,
  TNTClasses,
  Windows,
  SuperObject;


Const
  {$I TheAudioDB_APIKey.inc}

  maxReleaseYearDeviation = 2;
  maxCastCount = 10;

  tadbQueryInternetTimeout = 1500; // milliseconds

  SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE = -10; // Failed to scrape (Error from OnlineDB)
  SCRAPE_RESULT_ERROR_DB_UNAUTHORIZED = -401; // Failed to scrape (OnlineDB returned status = 401 - Unauthorized)
  SCRAPE_RESULT_ERROR_DB_OTHER_ERROR = -999; // Failed to scrape (OnlineDB returned status <> 200 - OK or there was some unrecognized error)

  {$IFDEF LOCALTRACE}
  CRLF             = #13+#10;
  {$ENDIF}

Type
  TtadbAlbumMetaDataRecord =
  Record
    tadb_idAlbum                : Int64;
    tadb_idArtist               : Int64;
    tadb_idLabel                : Int64;
    tadb_strAlbum               : WideString;
    tadb_strArtist              : WideString;
    tadb_intYearReleased        : Integer;
    tadb_strStyle               : WideString;
    tadb_strGenre               : WideString;
    tadb_strLabel               : WideString;
    tadb_strReleaseFormat       : WideString;
    tadb_intSales               : Int64;
    tadb_strAlbumThumb          : String;
    tadb_strAlbumThumbBack      : String;
    tadb_strAlbumCDart          : String;
    tadb_strAlbumSpine          : String;
    tadb_strDescriptionEN       : WideString;
    tadb_intLoved               : Int64;
    tadb_intScore               : Int64;
    tadb_intScoreVotes          : Int64;
    tadb_strReview              : WideString;
    tadb_strMood                : WideString;
    tadb_strTheme               : WideString;
    tadb_strSpeed               : WideString;
    tadb_strLocation            : WideString;
    tadb_strMusicBrainzID       : String;
    tadb_strMusicBrainzArtistID : String;
    tadb_strItunesID            : String;
    tadb_strAmazonID            : String;
    tadb_strLocked              : WideString;
  End;
  PtadbAlbumMetaDataRecord = ^TtadbAlbumMetaDataRecord;

  TtadbTrackMetaDataRecord =
  Record
    tadb_idAlbum                : Int64;
    tadb_idArtist               : Int64;
    tadb_idLyric                : Int64;
    tadb_strTrack               : WideString;
    tadb_strAlbum               : WideString;
    tadb_strArtist              : WideString;
    tadb_intDuration            : Int64;
    tadb_strGenre               : WideString;
    tadb_strMood                : WideString;
    tadb_strStyle               : WideString;
    tadb_strTheme               : WideString;
    tadb_strDescriptionEN       : WideString;
    tadb_strTrackThumb          : String;
    tadb_strTrackLyrics         : WideString;
    tadb_strMusicVid            : String;
    tadb_strMusicVidDirector    : WideString;
    tadb_strMusicVidCompany     : WideString;
    tadb_strMusicVidScreen1     : String;
    tadb_strMusicVidScreen2     : String;
    tadb_strMusicVidScreen3     : String;
    tadb_intMusicVidViews       : Int64;
    tadb_intMusicVidLikes       : Int64;
    tadb_intMusicVidDislikes    : Int64;
    tadb_intMusicVidFavorites   : Int64;
    tadb_intMusicVidComments    : Int64;
    tadb_intTrackNumber         : Int64;
    tadb_intLoved               : Int64;
    tadb_intScore               : Int64;
    tadb_intScoreVotes          : Int64;
    tadb_strMusicBrainzID       : String;
    tadb_strMusicBrainzAlbumID  : String;
    tadb_strMusicBrainzArtistID : String;
    tadb_strLocked              : WideString;
  End;
  PtadbTrackMetaDataRecord = ^TtadbTrackMetaDataRecord;


var
  csQuery          : TCriticalSection;
  TVSeriesIDList   : TList       = nil;
  QueryTSList      : TList       = nil;
  BaseURL          : String;
  Secure_BaseURL   : String;
  InitSuccess      : Boolean = False;
  PosterSizeList   : TStringList = nil;
  BackdropSizeList : TStringList = nil;
  StillSizeList    : TStringList = nil;


function  SearchTheAudioDB_Album(ArtistName, AlbumName : WideString; Secured : Boolean; searchMetaData : PtadbAlbumMetaDataRecord {$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : Integer;
function  SearchTheAudioDB_FileHash(Hash1,Hash2 : Int64; Secured : Boolean; searchMetaData : PtadbTrackMetaDataRecord {$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : Integer;
function  SearchTheAudioDB_TrackID(TrackID : Int64; Secured : Boolean; searchMetaData : PtadbTrackMetaDataRecord {$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : Integer;

procedure AlbumJSONtoSearchMetaData(var jAlbum : ISuperObject; searchMetaData : PtadbAlbumMetaDataRecord);
procedure TrackJSONtoSearchMetaData(var jTrack : ISuperObject; searchMetaData : PtadbTrackMetaDataRecord);
//procedure CheckAndAddToSearchLimitList;


implementation


uses
  SysUtils, TNTSysUtils, TheAudioDB_Misc_Utils_Unit, global_consts;

{
procedure CheckAndAddToSearchLimitList;
const
  dbLimit  : Integer = 40;
var
  qTS      : PInt64;
  I,qCount : Integer;
begin
  // Check that we're not overloading TheAudioDB's system (do they limit request? we limit to "dbLimit" requests in 10 seconds)
  New(qTS);
  Repeat
    qTS^   := TickCount64;
    qCount := 0;

    // Enter criticial section to prevent thread conflicts
    csQuery.Enter;
    Try
      For I := QueryTSList.Count-1 downto 0 do
      Begin
        If qTS^-PInt64(QueryTSList[I])^ > 10000 + 1000 then // we are adding one more second just to ensure a bit of headroom
        Begin
          // Delete entries older than 10 seconds
          Dispose(PInt64(QueryTSList[I]));
          QueryTSList.Delete(I);
        End
        Else Inc(qCount); // Count entries under 10 seconds
      End;
      If qCount >= dbLimit then Sleep(10);
    Finally
      csQuery.Leave;
    End;
  Until qCount < dbLimit-5; // using "dbLimit-5" search entries instead of "dbLimit" to ensure a bit of headroom.

  // Add current search to the limit list
  csQuery.Enter;
  Try
    QueryTSList.Add(qTS);
  Finally
    csQuery.Leave;
  End;
end;
}


procedure AlbumJSONtoSearchMetaData(var jAlbum : ISuperObject; searchMetaData : PtadbAlbumMetaDataRecord);
begin
  With searchMetaData^ do
  Begin
    tadb_strDescriptionEN       := StringReplace(StripNull(jAlbum.S['strDescriptionEN']),#10,'\n',[rfReplaceAll,rfIgnoreCase]);
    //tadb_strDescriptionEN       := UTF8StringToWideString(S);
    tadb_idAlbum                := StrToInt64Def(jAlbum.S['idAlbum'],-1);
    tadb_idArtist               := StrToInt64Def(jAlbum.S['idArtist'],-1);
    tadb_idLabel                := StrToInt64Def(jAlbum.S['idLabel'],-1);
    tadb_strAlbum               := UTF8Decode(StripNull(jAlbum.S['strAlbum']));
    tadb_strArtist              := UTF8Decode(StripNull(jAlbum.S['strArtist']));
    tadb_intYearReleased        := StrToInt64Def(jAlbum.S['intYearReleased'],-1);
    tadb_strStyle               := UTF8Decode(StripNull(jAlbum.S['strStyle']));
    tadb_strGenre               := UTF8Decode(StripNull(jAlbum.S['strGenre']));
    tadb_strLabel               := UTF8Decode(StripNull(jAlbum.S['strLabel']));
    tadb_strReleaseFormat       := UTF8Decode(StripNull(jAlbum.S['strReleaseFormat']));
    tadb_intSales               := StrToInt64Def(jAlbum.S['intSales'],-1);
    tadb_strAlbumThumb          := StripNull(jAlbum.S['strAlbumThumb']);
    tadb_strAlbumThumbBack      := StripNull(jAlbum.S['strAlbumThumbBack']);
    tadb_strAlbumCDart          := StripNull(jAlbum.S['strAlbumCDart']);
    tadb_strAlbumSpine          := StripNull(jAlbum.S['strAlbumSpine']);
    tadb_intLoved               := StrToInt64Def(jAlbum.S['intLoved'],-1);
    tadb_intScore               := StrToInt64Def(jAlbum.S['intScore'],-1);
    tadb_intScoreVotes          := StrToInt64Def(jAlbum.S['intScoreVotes'],-1);
    tadb_strReview              := StringReplace(StripNull(jAlbum.S['strReview']),#10,'\n',[rfReplaceAll,rfIgnoreCase]);
    tadb_strMood                := UTF8Decode(StripNull(jAlbum.S['strMood']));
    tadb_strTheme               := UTF8Decode(StripNull(jAlbum.S['strTheme']));
    tadb_strSpeed               := UTF8Decode(StripNull(jAlbum.S['strSpeed']));
    tadb_strLocation            := UTF8Decode(StripNull(jAlbum.S['strLocation']));
    tadb_strMusicBrainzID       := StripNull(jAlbum.S['strMusicBrainzID']);
    tadb_strMusicBrainzArtistID := StripNull(jAlbum.S['strMusicBrainzArtistID']);
    tadb_strItunesID            := StripNull(jAlbum.S['strItunesID']);
    tadb_strAmazonID            := StripNull(jAlbum.S['strAmazonID']);
    tadb_strLocked              := StripNull(jAlbum.S['strLocked']);
  End;
End;


procedure TrackJSONtoSearchMetaData(var jTrack : ISuperObject; searchMetaData : PtadbTrackMetaDataRecord);
begin
  With searchMetaData^ do
  Begin
    tadb_idAlbum                := StrToInt64Def(jTrack.S['idAlbum'],-1);
    tadb_idArtist               := StrToInt64Def(jTrack.S['idArtist'],-1);
    tadb_idLyric                := StrToInt64Def(jTrack.S['idLyric'],-1);
    tadb_strTrack               := UTF8Decode(StripNull(jTrack.S['strTrack']));
    tadb_strAlbum               := UTF8Decode(StripNull(jTrack.S['strAlbum']));
    tadb_strArtist              := UTF8Decode(StripNull(jTrack.S['strArtist']));
    tadb_intDuration            := StrToInt64Def(jTrack.S['intDuration'],-1);
    tadb_strGenre               := UTF8Decode(StripNull(jTrack.S['strGenre']));
    tadb_strMood                := UTF8Decode(StripNull(jTrack.S['strMood']));
    tadb_strStyle               := UTF8Decode(StripNull(jTrack.S['strStyle']));
    tadb_strTheme               := UTF8Decode(StripNull(jTrack.S['strTheme']));
    tadb_strDescriptionEN       := StringReplace(StripNull(jTrack.S['strDescriptionEN']),#10,'\n',[rfReplaceAll,rfIgnoreCase]);
    tadb_strTrackThumb          := StripNull(jTrack.S['strTrackThumb']);
    tadb_strTrackLyrics         := StringReplace(StripNull(jTrack.S['strTrackLyrics']),#10,'\n',[rfReplaceAll,rfIgnoreCase]);
    tadb_strMusicVid            := StripNull(jTrack.S['strMusicVid']);
    tadb_strMusicVidDirector    := UTF8Decode(StripNull(jTrack.S['strMusicVidDirector']));
    tadb_strMusicVidCompany     := UTF8Decode(StripNull(jTrack.S['strMusicVidCompany']));
    tadb_strMusicVidScreen1     := StripNull(jTrack.S['strMusicVidScreen1']);
    tadb_strMusicVidScreen2     := StripNull(jTrack.S['strMusicVidScreen2']);
    tadb_strMusicVidScreen3     := StripNull(jTrack.S['strMusicVidScreen3']);
    tadb_intMusicVidViews       := StrToInt64Def(jTrack.S['intMusicVidViews'],-1);
    tadb_intMusicVidLikes       := StrToInt64Def(jTrack.S['intMusicVidLikes'],-1);
    tadb_intMusicVidDislikes    := StrToInt64Def(jTrack.S['intMusicVidDislikes'],-1);
    tadb_intMusicVidFavorites   := StrToInt64Def(jTrack.S['intMusicVidFavorites'],-1);
    tadb_intMusicVidComments    := StrToInt64Def(jTrack.S['intMusicVidComments'],-1);
    tadb_intTrackNumber         := StrToInt64Def(jTrack.S['intTrackNumber'],-1);
    tadb_intLoved               := StrToInt64Def(jTrack.S['intLoved'],-1);
    tadb_intScore               := StrToInt64Def(jTrack.S['intScore'],-1);
    tadb_intScoreVotes          := StrToInt64Def(jTrack.S['intScoreVotes'],-1);
    tadb_strMusicBrainzID       := StripNull(jTrack.S['strMusicBrainzID']);
    tadb_strMusicBrainzAlbumID  := StripNull(jTrack.S['strMusicBrainzAlbumID']);
    tadb_strMusicBrainzArtistID := StripNull(jTrack.S['strMusicBrainzArtistID']);
    tadb_strLocked              := StripNull(jTrack.S['strLocked']);
  End;
end;


function SearchTheAudioDB_TrackID(TrackID : Int64; Secured : Boolean; searchMetaData : PtadbTrackMetaDataRecord {$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : Integer;
var
  sDownloadStatus    : String;
  dlResult           : Boolean;
  iDLError           : Integer;
  sList              : TStringList;
  sURL               : WideString;
  jObj               : ISuperObject;
  jTrack             : ISuperObject;
  jResults           : ISuperObject;
begin
  // http://www.theaudiodb.com/api/v1/json/0235897239871209235907/track.php?h=32724185

  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'SearchTheAudioDB_TrackID (before)');{$ENDIF}
  sDownloadStatus := '';
  Result := E_FAIL;

  With searchMetaData^ do
  Begin
    tadb_idAlbum                := -1;
    tadb_idArtist               := -1;
    tadb_idLyric                := -1;
    tadb_strTrack               := '';
    tadb_strAlbum               := '';
    tadb_strArtist              := '';
    tadb_intDuration            := -1;
    tadb_strGenre               := '';
    tadb_strMood                := '';
    tadb_strStyle               := '';
    tadb_strTheme               := '';
    tadb_strDescriptionEN       := '';
    tadb_strTrackThumb          := '';
    tadb_strTrackLyrics         := '';
    tadb_strMusicVid            := '';
    tadb_strMusicVidDirector    := '';
    tadb_strMusicVidCompany     := '';
    tadb_strMusicVidScreen1     := '';
    tadb_strMusicVidScreen2     := '';
    tadb_strMusicVidScreen3     := '';
    tadb_intMusicVidViews       := -1;
    tadb_intMusicVidLikes       := -1;
    tadb_intMusicVidDislikes    := -1;
    tadb_intMusicVidFavorites   := -1;
    tadb_intMusicVidComments    := -1;
    tadb_intTrackNumber         := -1;
    tadb_intLoved               := -1;
    tadb_intScore               := -1;
    tadb_intScoreVotes          := -1;
    tadb_strMusicBrainzID       := '';
    tadb_strMusicBrainzAlbumID  := '';
    tadb_strMusicBrainzArtistID := '';
    tadb_strLocked              := '';
  End;

  sURL := 'http://www.theaudiodb.com/api/v1/json/'+APIKey+'/track.php?h='+IntToStr(TrackID);

  //{$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'CheckAndAddToSearchLimitList');{$ENDIF}
  //CheckAndAddToSearchLimitList;

  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Download URL "'+sURL+'"');{$ENDIF}
  sList := TStringList.Create;

  Try
    dlResult := DownloadFileToStringList(sURL,sList,sDownloadStatus,iDLError,tadbQueryInternetTimeout{$IFDEF LOCALTRACE},ThreadID{$ENDIF});
  Except
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Download EXCEPTION!');{$ENDIF}
    dlResult := False;
  End;


  If dlResult = True then
  Begin
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Download successful');{$ENDIF}
    If sList.Count > 0 then
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Response ('+IntToStr(sList.Count)+' lines) :'+CRLF+CRLF+sList.Text);{$ENDIF}

      // Sample result
      // {
      //   "track":[
      //     {
      //       "idTrack":"32724185",
      //       "idAlbum":"2109615",
      //       "idArtist":"111239",
      //       "idLyric":"102254",
      //       "idIMVDB":null,
      //     * "strTrack":"Trouble",
      //     * "strAlbum":"Parachutes",
      //     * "strArtist":"Coldplay",
      //       "strArtistAlternate":null,
      //       "intCD":null,
      //       "intDuration":"270000",
      //     * "strGenre":"Pop-Rock",
      //       "strMood":null,
      //       "strStyle":null,
      //       "strTheme":null,
      //     * "strDescriptionEN":"\"Trouble\" is a song recorded by British alternative rock band Coldplay for their debut album, Parachutes. The band wrote the song and co-produced it with British record producer Ken Nelson. The song repeats the word \"trouble\" throughout the lyrics, and its musicscape is minimalist built around a piano.\n\nThe song was released on 26 October 2000 as the album's third single. It reached number 10 on the UK Singles Chart, making it the band's second Top 10 single in the country. Although \"Trouble\" failed to chart on the main singles chart in the United States, the music press deemed it almost as successful as its predecessor, \"Yellow\". Two different music videos for the single were released.",
      //     * "strTrackThumb":"http://www.theaudiodb.com/images/media/track/thumb/xqwrqt1340354430.jpg",
      //       "strTrackLyrics":"",
      //       "strMusicVid":"http://www.youtube.com/watch?v=kHg-PhseKOQ",
      //       "strMusicVidDirector":"Tim Hope",
      //       "strMusicVidCompany":"Passion Pictures",
      //       "strMusicVidScreen1":"http://www.theaudiodb.com/images/media/track/mvidscreen/xuvsus1364213274.jpg",
      //       "strMusicVidScreen2":"http://www.theaudiodb.com/images/media/track/mvidscreen/vrxrup1364213280.jpg",
      //       "strMusicVidScreen3":"http://www.theaudiodb.com/images/media/track/mvidscreen/rrptsw1364213287.jpg",
      //       "intMusicVidViews":"13331459",
      //       "intMusicVidLikes":"53946",
      //       "intMusicVidDislikes":"656",
      //       "intMusicVidFavorites":null,
      //       "intMusicVidComments":null,
      //     * "intTrackNumber":"6",
      //       "intLoved":"2",
      //     * "intScore":"10",
      //       "intScoreVotes":"1",
      //       "strMusicBrainzID":"5f1c33b7-de18-4845-b9a1-6385bfec68e8",
      //       "strMusicBrainzAlbumID":"1dc4c347-a1db-32aa-b14f-bc9cc507b843",
      //       "strMusicBrainzArtistID":"cc197bad-dc9c-440d-a5b5-d52ba2e14234",
      //       "strLocked":"unlocked"
      //     }
      //   ]
      // }

      jObj := SO(sList[0]);
      If jObj <> nil then
      Begin
        jResults := jObj.O['track'];
        If jResults <> nil then
        Begin
          If jResults.AsJSON <> 'null' then
          Begin
            // We don't loop the results, we're only using the first entry returned
            If jResults.AsArray.Length > 0 then
            Begin
              jTrack := jResults.AsArray[0];
              If jTrack <> nil then
              Begin
                TrackJSONtoSearchMetaData(jTrack,searchMetaData);
                Result := S_OK;
                jTrack.Clear;
                jTrack := nil;
              End
                else
              Begin
                {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Returned data is not valid - unable to get "album" index 0; Response: '+sList.Text);{$ENDIF}
                Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
              End;
            End
              else
            Begin
              {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Returned data is not valid - no "album" array; Response: '+sList.Text);{$ENDIF}
              Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
            End;
          End
          {$IFDEF LOCALTRACE}Else DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: jResults.AsJSON = null'){$ENDIF};
          jResults.Clear;
          jResults := nil;
        End
          else
        Begin
          {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Returned data is not valid - missing "album" section; Response: '+sList.Text);{$ENDIF}
          Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
        End;
        jObj.Clear;
        jObj := nil;
      End
        else
      Begin
        {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Returned data is not JSON Object; Response: '+sList.Text);{$ENDIF}
        Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
      End;
    End
      else
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Download returned no data; Status: "'+sDownloadStatus+'"; Response: '+sList.Text);{$ENDIF}
      Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
    End;
  End
    else
  Begin
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error downloading "'+sURL+'"!; ErrorCode: '+IntToStr(iDLError)+'; Status: "'+sDownloadStatus+'"; Response: '+sList.Text);{$ENDIF}
    if iDLError = S_OK then
      If sDownloadStatus = '401' then
        Result := SCRAPE_RESULT_ERROR_DB_UNAUTHORIZED else
        Result := SCRAPE_RESULT_ERROR_DB_OTHER_ERROR;
  End;
  sList.Free;
  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'SearchTheAudioDB_TrackID (after)');{$ENDIF}
end;


function SearchTheAudioDB_FileHash(Hash1,Hash2 : Int64; Secured : Boolean; searchMetaData : PtadbTrackMetaDataRecord {$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : Integer;
var
  sDownloadStatus    : String;
  iDLError           : Integer;
  sList              : TStringList;
  sURL               : WideString;
  jObj               : ISuperObject;
  jTrack             : ISuperObject;
  jResults           : ISuperObject;
  TrackID            : Int64;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'SearchTheAudioDB_FileHash (before)');{$ENDIF}
  sDownloadStatus := '';
  Result := E_FAIL;

  sURL := 'http://www.theaudiodb.com/api/v1/json/'+APIKey+'/search-hash.php?h1='+IntToHex(Hash1,16)+'&h2='+IntToHex(Hash2,16);

  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'CheckAndAddToSearchLimitList');{$ENDIF}
  //CheckAndAddToSearchLimitList;

  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Download URL "'+sURL+'"');{$ENDIF}
  sList := TStringList.Create;
  If DownloadFileToStringList(sURL,sList,sDownloadStatus,iDLError,tadbQueryInternetTimeout{$IFDEF LOCALTRACE},ThreadID{$ENDIF}) = True then
  Begin
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Download successful');{$ENDIF}
    If sList.Count > 0 then
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Response ('+IntToStr(sList.Count)+' lines) :'+CRLF+CRLF+sList.Text);{$ENDIF}

      // Sample result
      // {
      //   "tracks":[
      //     {
      //       "idHash":"22933",
      //       "strHash1":"EB8A4D545F4B6895",
      //       "strHash2":"3862F1254AEEDA11",
      //       "strUser":"zag",
      //       "idArtist":"111239",
      //       "idAlbum":"2109615",
      //       "idTrack":"32724185",
      //       "mbArtist":"cc197bad-dc9c-440d-a5b5-d52ba2e14234",
      //       "mbAlbum":"1dc4c347-a1db-32aa-b14f-bc9cc507b843",
      //       "mbTrack":"5f1c33b7-de18-4845-b9a1-6385bfec68e8",
      //       "strArtist":"Coldplay",
      //       "strAlbum":"Parachutes",
      //       "strTrack":"Trouble",
      //       "strFormat":"mp3",
      //       "strFilesize":"5979251",
      //       "strGenre":"Alternative",
      //       "strTrackNumber":"6",
      //       "strEncoded":"",
      //       "strRecorded":"2000",
      //       "strGroup":"",
      //       "strFolder":"Coldplay-Parachutes-(Import)-2000-DNR",
      //       "strFile":"06-coldplay-trouble-dnr.mp3",
      //       "strType":"zoom",
      //       "strMatches":null,
      //       "date":"0000-00-00 00:00:00"
      //     }
      //   ]
      // }

      jObj := SO(sList[0]);
      If jObj <> nil then
      Begin
        jResults := jObj.O['tracks'];
        If jResults <> nil then
        Begin
          If jResults.AsJSON <> 'null' then
          Begin
            // We don't loop the results, we're only using the first entry returned
            If jResults.AsArray.Length > 0 then
            Begin
              jTrack := jResults.AsArray[0];
              If jTrack <> nil then
              Begin
                TrackID := StrToInt64Def(jTrack.S['idTrack'],-1);
                If TrackID > -1 then
                Begin
                  Result := SearchTheAudioDB_TrackID(TrackID,Secured,searchMetaData{$IFDEF LOCALTRACE},ThreadID{$ENDIF});
                End;
                jTrack.Clear;
                jTrack := nil;
              End
                else
              Begin
                {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Returned data is not valid - unable to get "album" index 0; Response: '+sList.Text);{$ENDIF}
                Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
              End;
            End
              else
            Begin
              {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Returned data is not valid - no "album" array; Response: '+sList.Text);{$ENDIF}
              Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
            End;
          End
          {$IFDEF LOCALTRACE}Else DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: jResults.AsJSON = null'){$ENDIF};
          jResults.Clear;
          jResults := nil;
        End
          else
        Begin
          {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Returned data is not valid - missing "album" section; Response: '+sList.Text);{$ENDIF}
          Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
        End;
        jObj.Clear;
        jObj := nil;
      End
        else
      Begin
        {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Returned data is not JSON Object; Response: '+sList.Text);{$ENDIF}
        Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
      End;
    End
      else
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Download returned no data; Status: "'+sDownloadStatus+'"; Response: '+sList.Text);{$ENDIF}
      Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
    End;
  End
    else
  Begin
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error downloading "'+sURL+'"!; ErrorCode: '+IntToStr(iDLError)+'; Status: "'+sDownloadStatus+'"; Response: '+sList.Text);{$ENDIF}
    if iDLError = S_OK then
      If sDownloadStatus = '401' then
        Result := SCRAPE_RESULT_ERROR_DB_UNAUTHORIZED else
        Result := SCRAPE_RESULT_ERROR_DB_OTHER_ERROR;
  End;
  sList.Free;
  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'SearchTheAudioDB_FileHash (after)');{$ENDIF}
end;


function SearchTheAudioDB_Album(ArtistName, AlbumName : WideString; Secured : Boolean; searchMetaData : PtadbAlbumMetaDataRecord {$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : Integer;
var
  I                  : Integer;
  jObj               : ISuperObject;
  jAlbum             : ISuperObject;
  jResults           : ISuperObject;
  sDownloadStatus    : String;
  iDLError           : Integer;
  sList              : TStringList;
  sURL               : WideString;

begin
  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'SearchTheMovieDB_Album (before)');{$ENDIF}
  sDownloadStatus := '';
  Result := E_FAIL;

  With searchMetaData^ do
  Begin
    tadb_idAlbum                := -1;
    tadb_idArtist               := -1;
    tadb_idLabel                := -1;
    tadb_strAlbum               := '';
    tadb_strArtist              := '';
    tadb_intYearReleased        := -1;
    tadb_strStyle               := '';
    tadb_strGenre               := '';
    tadb_strLabel               := '';
    tadb_strReleaseFormat       := '';
    tadb_intSales               := -1;
    tadb_strAlbumThumb          := '';
    tadb_strAlbumThumbBack      := '';
    tadb_strAlbumCDart          := '';
    tadb_strAlbumSpine          := '';
    tadb_strDescriptionEN       := '';
    tadb_intLoved               := -1;
    tadb_intScore               := -1;
    tadb_intScoreVotes          := -1;
    tadb_strReview              := '';
    tadb_strMood                := '';
    tadb_strTheme               := '';
    tadb_strSpeed               := '';
    tadb_strLocation            := '';
    tadb_strMusicBrainzID       := '';
    tadb_strMusicBrainzArtistID := '';
    tadb_strItunesID            := '';
    tadb_strAmazonID            := '';
    tadb_strLocked              := '';
  End;

  //{$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'CheckAndAddToSearchLimitList');{$ENDIF}
  //CheckAndAddToSearchLimitList;

  If ArtistName <> '' then
    sURL := 'http://www.theaudiodb.com/api/v1/json/'+APIKey+'/searchalbum.php?s='+URLEncodeUTF8(ArtistName)+'&a='+URLEncodeUTF8(AlbumName) else
    sURL := 'http://www.theaudiodb.com/api/v1/json/'+APIKey+'/searchalbum.php?a='+URLEncodeUTF8(AlbumName);
  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Download URL "'+sURL+'"');{$ENDIF}
  sList := TStringList.Create;

  If DownloadFileToStringList(sURL,sList,sDownloadStatus,iDLError,tadbQueryInternetTimeout{$IFDEF LOCALTRACE},ThreadID{$ENDIF}) = True then
  Begin
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Download successful');{$ENDIF}
    If sList.Count > 0 then
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Response ('+IntToStr(sList.Count)+' lines) :'+CRLF+CRLF+sList.Text);{$ENDIF}

      // Sample result
      //{
      //  "album":[
      //    {
      //      "idAlbum":"2112977",
      //      "idArtist":"111493",
      //      "idLabel":"46036",
      //      "strAlbum":"21",
      //      "strArtist":"Adele",
      //      "intYearReleased":"2011",
      //      "strStyle":"Rock/Pop",
      //      "strGenre":"Soul",
      //      "strLabel":"XL Recordings",
      //      "strReleaseFormat":"Album",
      //      "intSales":"26000000",
      //      "strAlbumThumb":"http://media.theaudiodb.com/images/media/album/thumb/qqvwut1474978008.jpg",
      //      "strAlbumThumbBack":"http://www.theaudiodb.com/images/media/album/thumbback/yvvtsv1452670855.jpg",
      //      "strAlbumCDart":"http://www.theaudiodb.com/images/media/album/cdart/21-4dc971bd53cbd.png",
      //      "strAlbumSpine":"http://www.theaudiodb.com/images/media/album/spine/qrxrst1453237437.jpg",
      //      "strDescriptionEN":"21 is the second studio album by British ...",
      //      "intLoved":"3",
      //      "intScore":"9.8",
      //      "intScoreVotes":"5",
      //      "strReview":"One of the few real beneficiaries of The X Factor effect...",
      //      "strMood":"In Love",
      //      "strTheme":"",
      //      "strSpeed":"Slow",
      //      "strLocation":null,
      //      "strMusicBrainzID":"e4174758-d333-4a8e-a31f-dd0edd51518e",
      //      "strMusicBrainzArtistID":"cc2c9c3c-b7bc-4b8b-84d8-4fbd8779e493",
      //      "strItunesID":null,
      //      "strAmazonID":null,
      //      "strLocked":"unlocked"
      //    }
      //  ]
      //}

      Try
        jObj := SO(sList[0]);
      Except
        {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Exception on jObj');{$ENDIF}
      End;
      If jObj <> nil then
      Begin
        {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'JSON is Valid');{$ENDIF}
        jResults := jObj.O['album'];
        If jResults <> nil then
        Begin
          {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Found Album');{$ENDIF}
          If jResults.AsJSON <> 'null' then
          Begin
            {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Album is Valid');{$ENDIF}
            // We don't loop the results, we're only using the first entry returned
            If jResults.AsArray.Length > 0 then
            //For I := 0 to jResults.AsArray.Length-1 do
            Begin
              {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Album has Entries');{$ENDIF}
              jAlbum := jResults.AsArray[0{I}];
              If jAlbum <> nil then
              Begin
                {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Extracting Meta Data (before)');{$ENDIF}
                AlbumJSONtoSearchMetaData(jAlbum,searchMetaData);
                {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Extracting Meta Data (after)');{$ENDIF}
                Result := S_OK;
                jAlbum.Clear;
                jAlbum := nil;
                {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Clear 1');{$ENDIF}
              End
                else
              Begin
                {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Returned data is not valid - unable to get "album" index 0; Response: '+sList.Text);{$ENDIF}
                Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
              End;
            End
              else
            Begin
              {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Returned data is not valid - no "album" array; Response: '+sList.Text);{$ENDIF}
              Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
            End;
          End
          {$IFDEF LOCALTRACE}Else DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: jResults.AsJSON = null'){$ENDIF};
          jResults.Clear;
          jResults := nil;
          {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Clear 2');{$ENDIF}
        End
          else
        Begin
          {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Returned data is not valid - missing "album" section; Response: '+sList.Text);{$ENDIF}
          Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
        End;
        jObj.Clear;
        jObj := nil;
        {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Clear 3');{$ENDIF}
      End
        else
      Begin
        {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Returned data is not JSON Object; Response: '+sList.Text);{$ENDIF}
        Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
      End;
    End
      else
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error: Download returned no data; Status: "'+sDownloadStatus+'"; Response: '+sList.Text);{$ENDIF}
      Result := SCRAPE_RESULT_ERROR_DB_UNSUPPORTED_RESPONSE;
    End;
  End
    else
  Begin
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error downloading "'+sURL+'"!; ErrorCode: '+IntToStr(iDLError)+'; Status: "'+sDownloadStatus+'"; Response: '+sList.Text);{$ENDIF}
    //{$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'Error downloading "'+sURL+'"');{$ENDIF}
    if iDLError = S_OK then
      If sDownloadStatus = '401' then
        Result := SCRAPE_RESULT_ERROR_DB_UNAUTHORIZED else
        Result := SCRAPE_RESULT_ERROR_DB_OTHER_ERROR;
    Result := SCRAPE_RESULT_ERROR_DB_OTHER_ERROR;    
  End;
  sList.Free;
  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'SearchTheMovieDB (after)');{$ENDIF}
end;


end.
