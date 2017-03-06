{$I SCRAPER_DEFINES.INC}

unit TheAudioDB_misc_utils_unit;


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

      { This sample code uses the TNT Delphi Unicode Controls (compatiable
        with the last free version) to handle a few unicode tasks. }

interface

uses
  Windows, Classes, SyncObjs, TNTClasses;


function  TickCount64 : Int64;

{$IFDEF LOCALTRACE}
procedure DebugMsgF(FileName : WideString; Txt : WideString);
procedure DebugMsgFT(FileName : WideString; Txt : WideString);
{$ENDIF}

function  DownloadFileToStringList(URL : String; fStream : TStringList; var Status : String; var ErrorCode: Integer; TimeOut : DWord{$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : Boolean; overload;
function  DownloadFileToStream(URL : String; fStream : TMemoryStream; var Status : String; var ErrorCode: Integer; TimeOut : DWord{$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : Boolean; overload;
function  DownloadImageToFile(URL : String; ImageFilePath, ImageFileName : WideString; var Status : String; var ErrorCode: Integer; TimeOut : DWord{$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : Boolean; overload;

function  URLEncodeUTF8(stInput : widestring) : string;

function  SetRegDWord(BaseKey : HKey; SubKey : String; KeyEntry : String; KeyValue : Integer) : Boolean;
function  GetRegDWord(BaseKey : HKey; SubKey : String; KeyEntry : String) : Integer;

function  AddBackSlash(S : WideString) : WideString; Overload;
function  ConvertCharsToSpaces(S : WideString) : WideString;

procedure FileExtIntoStringList(fPath,fExt : WideString; fList : TTNTStrings; Recursive : Boolean);
function  UTF8StringToWideString(Const S : UTF8String) : WideString;
function  StripNull(S : String) : String;

procedure CalcGabestHash(const Stream: TStream; var Hash1,Hash2 : Int64); overload;
procedure CalcGabestHash(const FileName: WideString; var Hash1,Hash2 : Int64); overload;
function  EncodeDuration(Dur : Integer) : WideString;
//function  get_JSON(sURL : String{$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : String;

{$IFDEF LOCALTRACE}
const
  ScrapeLog        : String = 'c:\log\ScrapeTheAudioDB_';
  ScrapeLogExt     : String = '.txt';
{$ENDIF}

var
  csParser         : TCriticalSection;
{$IFDEF LOCALTRACE}
  csDebug          : TCriticalSection;
  DebugStartTime   : Int64 = -1;
  qTimer64Freq     : Int64;
{$ENDIF}

implementation

uses
  SysUtils, TNTSysUtils, wininet{, IdHTTP, IdCompressorZLib};


const
  URLIdentifier     : String = 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)';

var
  TickCountLast    : DWORD = 0;
  TickCountBase    : Int64 = 0;


function TickCount64 : Int64;
begin
  Result := GetTickCount;
  If Result < TickCountLast then TickCountBase := TickCountBase+$100000000;
  TickCountLast := Result;
  Result := Result+TickCountBase;
end;

{$IFDEF LOCALTRACE}
procedure DebugMsgFT(FileName : WideString; Txt : WideString);
var
  S,S1 : String;
  i64  : Int64;
begin
  csDebug.Enter;
  Try
    If FileName <> '' then
    Begin
      QueryPerformanceCounter(i64);
      S := FloatToStrF(((i64-DebugStartTime)*1000) / qTimer64Freq,ffFixed,15,3);
      While Length(S) < 12 do S := ' '+S;
      S1 := DateToStr(Date)+' '+TimeToStr(Time);
      DebugMsgF(FileName,S1+' ['+S+'] : '+Txt);
    End;
  Finally
    csDebug.Leave;
  End;
end;


procedure DebugMsgF(FileName : WideString; Txt : WideString);
var
  fStream  : TTNTFileStream;
  S        : String;
begin
  If FileName <> '' then
  Begin
    //csDebug.Enter;
    //Try
      If WideFileExists(FileName) = True then
      Begin
        Try
          fStream := TTNTFileStream.Create(FileName,fmOpenWrite);
        Except
          fStream := nil;
        End;
      End
        else
      Begin
        Try
          fStream := TTNTFileStream.Create(FileName,fmCreate);
        Except
          fStream := nil;
        End;
      End;
      If fStream <> nil then
      Begin
        S := UTF8Encode(Txt)+CRLF;
        fStream.Seek(0,soFromEnd);
        fStream.Write(S[1],Length(S));
        fStream.Free;
       End;
    //Finally
    //  csDebug.Leave;
    //End;
  End;
end;
{$ENDIF}

function  DownloadFileToStringList(URL : String; fStream : TStringList; var Status : String; var ErrorCode: Integer; TimeOut : DWord{$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : Boolean;
var
  MemStream : TMemoryStream;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStringList (before)');{$ENDIF}
  Result := False;
  If fStream <> nil then
  Begin
    MemStream := TMemoryStream.Create;
    Result := DownloadFileToStream(URL,MemStream,Status,ErrorCode,TimeOut{$IFDEF LOCALTRACE},ThreadID{$ENDIF});
    MemStream.Position := 0;
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStringList: Load from memory stream');{$ENDIF}
    fStream.LoadFromStream(MemStream);
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStringList: Free memory stream');{$ENDIF}
    MemStream.Free;
  End;
  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStringList (after)');{$ENDIF}
end;


function DownloadFileToStream(URL : String; fStream : TMemoryStream; var Status : String; var ErrorCode: Integer; TimeOut : DWord{$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : Boolean;
type
  DLBufType = Array[0..8192] of Char;
const
  MaxRetryAttempts = 5;
  RetryInterval = 1; //seconds
var
  NetHandle  : HINTERNET;
  URLHandle  : HINTERNET;
  DLBuf      : ^DLBufType;
  BytesRead  : DWord;
  infoBuffer : ^DLBufType;
  bufLen     : DWORD;
  Tmp        : DWord;
  iAttemptsLeft : Integer;
  AttemptAgain  : Boolean;
  RetryAfter: String;
  qiResult   : Boolean;
  irfResult  : Boolean;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream (before)');{$ENDIF}
  Result := False;
  Status := '';
  ErrorCode := 0;
  If fStream <> nil then
  Begin
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: Memory stream valid');{$ENDIF}
    Try
      NetHandle := InternetOpen(PChar(URLIdentifier),INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
    Except
      {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: Exception on InternetOpen');{$ENDIF}
    End;
    If Assigned(NetHandle) then
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: NetHandle assigned');{$ENDIF}
      If TimeOut > 0 then
      Begin
        {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: InternetSetOption (before)');{$ENDIF}
        InternetSetOption(NetHandle,INTERNET_OPTION_CONNECT_TIMEOUT,@TimeOut,Sizeof(TimeOut));
        InternetSetOption(NetHandle,INTERNET_OPTION_SEND_TIMEOUT   ,@TimeOut,Sizeof(TimeOut));
        InternetSetOption(NetHandle,INTERNET_OPTION_RECEIVE_TIMEOUT,@TimeOut,Sizeof(TimeOut));
        {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: InternetSetOption (after)');{$ENDIF}
      End;

      //iAttemptsLeft := MaxRetryAttempts;
      //repeat
        //AttemptAgain := False;

        Try
          UrlHandle := InternetOpenUrl(NetHandle,PChar(URL),nil,0,INTERNET_FLAG_RELOAD,0);
        Except
          {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: Exception on InternetOpenUrl');{$ENDIF}
        End;
        If Assigned(UrlHandle) then
        Begin
          {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: URLHandle assigned');{$ENDIF}

          New(InfoBuffer);
          tmp    := 0;
          bufLen := Sizeof(DLBufType)-1;
          //ZeroMemory(InfoBuffer,BufLen);
          FillChar(InfoBuffer^,BufLen,0);

          Try
            qiResult := HttpQueryInfo(UrlHandle,HTTP_QUERY_STATUS_CODE,infoBuffer,bufLen,tmp);
          Except
            {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: Exception on HttpQueryInfo');{$ENDIF}
            qiResult := False;
          End;

          If qiResult = True then
          Begin
            Status := infoBuffer^;

            (*RetryAfter := '';
            If Status = '429' then
            Begin
              {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: Status 429! (retry-after)');{$ENDIF}
              //To get all headers use the following code
              //  HttpQueryInfo(UrlHandle,HTTP_QUERY_RAW_HEADERS_CRLF,@Headers[0],bufLen,tmp);
              //for guidance and hints on buffer sizes and in/out params see:
              //  https://msdn.microsoft.com/en-us/library/windows/desktop/aa385373%28v=vs.85%29.aspx

              //Retry-After
              //X-RateLimit-Limit: 40
              //X-RateLimit-Remaining: 39
              //X-RateLimit-Reset: 1453056622
              bufLen := Length(infoBuffer^);
              infoBuffer^ := 'Retry-After';
              if HttpQueryInfo(UrlHandle,HTTP_QUERY_CUSTOM,infoBuffer,bufLen,tmp) then
                RetryAfter := infoBuffer^
              else RetryAfter := '';
            End
            {$IFDEF LOCALTRACE}Else DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: Status '+Status){$ENDIF};*)

            {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: Start Download');{$ENDIF}
            New(DLBuf);
            fStream.Clear;
            BufLen := SizeOf(DLBufType)-1;
            Repeat
              //ZeroMemory(DLBuf,Sizeof(DLBufType));
              FillChar(DLBuf^,Sizeof(DLBufType),0);
              Try
                irfResult := InternetReadFile(UrlHandle,DLBuf,BufLen,BytesRead)
              Except
                {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: Exception on InternetReadFile');{$ENDIF}
                irfResult := false;
              End;

              If irfResult = True then If BytesRead > 0 then
              Try
                fStream.Write(DLBuf^,BytesRead);
              Except
                {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: Exception on fStream.Write');{$ENDIF}
              End;
            Until (BytesRead = 0);
            Dispose(DLBuf);
            {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: End Download');{$ENDIF}

            If Status = '200' then Result := True;
            (*else If Status = '429' then // 429 - Too Many Requests
            Begin
              AttemptAgain := True;
              Dec(iAttemptsLeft);
              Sleep(1000 * StrToIntDef(RetryAfter, RetryInterval));
             {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: Retry Attempt');{$ENDIF}
            End*)
          End
          {$IFDEF LOCALTRACE}Else DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: HttpQueryInfo returned false!'){$ENDIF};
          Dispose(InfoBuffer);
          {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: Close URLHandle');{$ENDIF}
          InternetCloseHandle(UrlHandle);
        End
        Else ErrorCode := GetLastError;
      //until not (AttemptAgain and (iAttemptsLeft > 0));
      {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: Close NetHandle');{$ENDIF}
      InternetCloseHandle(NetHandle);
    End
    {$IFDEF LOCALTRACE}Else DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream: NetHandle not assigned');{$ENDIF};
  End;
  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'DownloadFileToStream (after)');{$ENDIF}
end;


function  DownloadImageToFile(URL : String; ImageFilePath, ImageFileName : WideString; var Status : String; var ErrorCode: Integer; TimeOut : DWord{$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : Boolean;
var
  iStream : TMemoryStream;
  fStream : TTNTFileStream;
begin
  Result := False;
  // Download image to memory stream
  iStream := TMemoryStream.Create;
  iStream.Clear;
  If DownloadFileToStream(URL,iStream,Status,ErrorCode,TimeOut{$IFDEF LOCALTRACE},ThreadID{$ENDIF}) = True then
  Begin
    If iStream.Size > 0 then
    Begin
      // Create the destination folder if it doesn't exist
      If WideDirectoryExists(ImageFilePath) = False then WideForceDirectories(ImageFilePath);

      // Save the source image to disk
      Try
        fStream := TTNTFileStream.Create(ImageFilePath+ImageFileName,fmCreate);
      Except
        fStream := nil
      End;
      If fStream <> nil then
      Begin
        iStream.Position := 0;
        Try
          fStream.CopyFrom(iStream,iStream.Size);
          Result := True;
        Finally
          fStream.Free;
        End;
      End;
    End;
  End;
  iStream.Free;
end;




function URLEncodeUTF8(stInput : widestring) : string;
const
  Hex : array[0..255] of string = (
    '%00', '%01', '%02', '%03', '%04', '%05', '%06', '%07',
    '%08', '%09', '%0a', '%0b', '%0c', '%0d', '%0e', '%0f',
    '%10', '%11', '%12', '%13', '%14', '%15', '%16', '%17',
    '%18', '%19', '%1a', '%1b', '%1c', '%1d', '%1e', '%1f',
    '%20', '%21', '%22', '%23', '%24', '%25', '%26', '%27',
    '%28', '%29', '%2a', '%2b', '%2c', '%2d', '%2e', '%2f',
    '%30', '%31', '%32', '%33', '%34', '%35', '%36', '%37',
    '%38', '%39', '%3a', '%3b', '%3c', '%3d', '%3e', '%3f',
    '%40', '%41', '%42', '%43', '%44', '%45', '%46', '%47',
    '%48', '%49', '%4a', '%4b', '%4c', '%4d', '%4e', '%4f',
    '%50', '%51', '%52', '%53', '%54', '%55', '%56', '%57',
    '%58', '%59', '%5a', '%5b', '%5c', '%5d', '%5e', '%5f',
    '%60', '%61', '%62', '%63', '%64', '%65', '%66', '%67',
    '%68', '%69', '%6a', '%6b', '%6c', '%6d', '%6e', '%6f',
    '%70', '%71', '%72', '%73', '%74', '%75', '%76', '%77',
    '%78', '%79', '%7a', '%7b', '%7c', '%7d', '%7e', '%7f',
    '%80', '%81', '%82', '%83', '%84', '%85', '%86', '%87',
    '%88', '%89', '%8a', '%8b', '%8c', '%8d', '%8e', '%8f',
    '%90', '%91', '%92', '%93', '%94', '%95', '%96', '%97',
    '%98', '%99', '%9a', '%9b', '%9c', '%9d', '%9e', '%9f',
    '%a0', '%a1', '%a2', '%a3', '%a4', '%a5', '%a6', '%a7',
    '%a8', '%a9', '%aa', '%ab', '%ac', '%ad', '%ae', '%af',
    '%b0', '%b1', '%b2', '%b3', '%b4', '%b5', '%b6', '%b7',
    '%b8', '%b9', '%ba', '%bb', '%bc', '%bd', '%be', '%bf',
    '%c0', '%c1', '%c2', '%c3', '%c4', '%c5', '%c6', '%c7',
    '%c8', '%c9', '%ca', '%cb', '%cc', '%cd', '%ce', '%cf',
    '%d0', '%d1', '%d2', '%d3', '%d4', '%d5', '%d6', '%d7',
    '%d8', '%d9', '%da', '%db', '%dc', '%dd', '%de', '%df',
    '%e0', '%e1', '%e2', '%e3', '%e4', '%e5', '%e6', '%e7',
    '%e8', '%e9', '%ea', '%eb', '%ec', '%ed', '%ee', '%ef',
    '%f0', '%f1', '%f2', '%f3', '%f4', '%f5', '%f6', '%f7',
    '%f8', '%f9', '%fa', '%fb', '%fc', '%fd', '%fe', '%ff');
var
  iLen,iIndex : integer;
  stEncoded   : string;
  ch          : widechar;
begin
  iLen := Length(stInput);
  stEncoded := '';
  for iIndex := 1 to iLen do
  begin
    ch := stInput[iIndex];
    If (ch >= 'A') and (ch <= 'Z') then stEncoded := stEncoded + ch
      else
    If (ch >= 'a') and (ch <= 'z') then stEncoded := stEncoded + ch
      else
    If (ch >= '0') and (ch <= '9') then stEncoded := stEncoded + ch
      else
    If (ch = ' ') then stEncoded := stEncoded + '%20'//'+'
      else
    If ((ch = '-') or (ch = '_') or (ch = '.') or (ch = '!') or (ch = '*') or (ch = '~') or (ch = '\')  or (ch = '(') or (ch = ')')) then stEncoded := stEncoded + ch
      else
    If (Ord(ch) <= $07F) then stEncoded := stEncoded + hex[Ord(ch)]
      else
    If (Ord(ch) <= $7FF) then
    begin
      stEncoded := stEncoded + hex[$c0 or (Ord(ch) shr 6)];
      stEncoded := stEncoded + hex[$80 or (Ord(ch) and $3F)];
    end
      else
    begin
      stEncoded := stEncoded + hex[$e0 or (Ord(ch) shr 12)];
      stEncoded := stEncoded + hex[$80 or ((Ord(ch) shr 6) and ($3F))];
      stEncoded := stEncoded + hex[$80 or ((Ord(ch)) and ($3F))];
    end;
  end;
  result := (stEncoded);
end;


function SetRegDWord(BaseKey : HKey; SubKey : String; KeyEntry : String; KeyValue : Integer) : Boolean;
var
  RegHandle : HKey;
  I         : Integer;
begin
  Result := False;
  If RegCreateKeyEx(BaseKey,PChar(SubKey),0,nil,REG_OPTION_NON_VOLATILE,KEY_ALL_ACCESS,nil,RegHandle,@I) = ERROR_SUCCESS then
  Begin
    If RegSetValueEx(RegHandle,PChar(KeyEntry),0,REG_DWORD,@KeyValue,4) = ERROR_SUCCESS then Result := True;
    RegCloseKey(RegHandle);
  End;
end;


function GetRegDWord(BaseKey : HKey; SubKey : String; KeyEntry : String) : Integer;
var
  RegHandle : HKey;
  RegType   : LPDWord;
  BufSize   : LPDWord;
  KeyValue  : Integer;
begin
  Result := -1;
  If RegOpenKeyEx(BaseKey,PChar(SubKey),0,KEY_READ,RegHandle) = ERROR_SUCCESS then
  Begin
    New(RegType);
    New(BufSize);
    RegType^ := Reg_DWORD;
    BufSize^ := 4;
    If RegQueryValueEx(RegHandle,PChar(KeyEntry),nil,RegType,@KeyValue,BufSize) = ERROR_SUCCESS then
    Begin
      Result := KeyValue;
    End;
    Dispose(BufSize);
    Dispose(RegType);
    RegCloseKey(RegHandle);
  End;
end;



function AddBackSlash(S : WideString) : WideString; Overload;
var I : Integer;
begin
  I := Length(S);
  If I > 0 then If (S[I] <> '\') and (S[I] <> '/') then S := S+'\';
  Result := S;
end;


function ConvertCharsToSpaces(S : WideString) : WideString;
begin
  Result := TNT_WideStringReplace(TNT_WideStringReplace(TNT_WideStringReplace(S,'-', ' ', [rfReplaceAll]), '.', ' ', [rfReplaceAll]), '_', ' ', [rfReplaceAll]);
end;


procedure FileExtIntoStringList(fPath,fExt : WideString; fList : TTNTStrings; Recursive : Boolean);
var
  sRec : TSearchRecW;
begin
  If WideFindFirst(fPath+'*.*',faAnyFile,sRec) = 0 then
  Begin
    Repeat
      If (Recursive = True) and (sRec.Attr and faDirectory = faDirectory) and (sRec.Name <> '.') and (sRec.Name <> '..') then
      Begin
        FileExtIntoStringList(AddBackSlash(fPath+sRec.Name),fExt,fList,Recursive);
      End
        else
      If (sRec.Attr and faVolumeID = 0) and (sRec.Attr and faDirectory = 0) then
      Begin
        If WideCompareText(WideExtractFileExt(sRec.Name),fExt) = 0 then
          fList.Add(fPath+sRec.Name);
      End;
    Until WideFindNext(sRec) <> 0;
    WideFindClose(sRec);
  End;
end;


function UTF8StringToWideString(Const S : UTF8String) : WideString;
var
  iLen :Integer;
  sw   :WideString;
begin
  Result := '';
  if Length(S) = 0 then Exit;
  iLen := MultiByteToWideChar(CP_UTF8,0,PAnsiChar(s),-1,nil,0);
  SetLength(sw,iLen);
  MultiByteToWideChar(CP_UTF8,0,PAnsiChar(s),-1,PWideChar(sw),iLen);
  iLen := Pos(#0,sw);
  If iLen > 0 then SetLength(sw,iLen-1);
  Result := sw;
end;


function StripNull(S : String) : String;
begin
  If CompareText(S,'null') = 0 then Result := '' else Result := S;
end;



procedure CalcGabestHash(const Stream: TStream; var Hash1,Hash2 : Int64); overload;
var
  Hash1Ofs : Int64;
  Hash2Ofs : Int64;
  sSize    : Int64;
const
  HashPartSize = 1 shl 16; // 64 KiB

  procedure HashFromStream(const Stream: TStream; var Hash: Int64);
  var
    I      : Integer;
    Buffer : Array[0..HashPartSize div SizeOf(Int64)-1] of Int64;
  begin
    Stream.ReadBuffer(Buffer[0], SizeOf(Buffer));
    For I := Low(buffer) to High(buffer) do Inc(Hash, Buffer[i]);
  end;

begin
  Hash1    := 0;
  Hash2    := 0;
  Hash1Ofs := 0;
  Hash2Ofs := 0;

  sSize := Stream.Size;

  // The hash offset position within the file is determined by the file size to support smaller file
  // sizes, while allowing larger TAG data (embedded images) to be changed without affecting both hashes (on files over 2048KiB).

  // 256KiB - 2048KiB
  If (sSize >= 1 shl 18) and (sSize < 1 shl 21) then
  Begin
    Hash1Ofs := 1 shl 17;               // Hash1 offset is  128KiB from the start of the file
    Hash2Ofs := Stream.Size-(1 shl 17); // Hash2 offset is  128KiB from the end of the file
  End
    else
  // 2048KiB - MAX
  If (sSize >= 1 shl 21) then
  Begin
    Hash1Ofs := 1 shl 20;               // Hash1 offset is 1024KiB from the start of the file
    Hash2Ofs := Stream.Size-(1 shl 20); // Hash2 offset is 1024KiB from the end of the file
  End;

  If Hash1Ofs <> 0 then
  Begin
    // Hash1:
    Stream.Position:= Hash1Ofs;
    HashFromStream(Stream, Hash1);

    // Hash2:
    Stream.Position:= Hash2Ofs;
    HashFromStream(Stream, Hash2);
  End;

  // use "IntToHex(Hash1, 16);" to get a string and "StrToInt64('$' + hash);" to get your Int64 back
end;


procedure CalcGabestHash(const FileName: WideString; var Hash1,Hash2 : Int64); overload;
var
  Stream: TStream;
begin
  Stream := TTNTFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  Try
    CalcGabestHash(Stream,Hash1,Hash2);
  Except
    Hash1 := 0;
    Hash2 := 0;
  End;
  Stream.Free;
end;


function EncodeDuration(Dur : Integer) : WideString;
var
  dHours   : Integer;
  dMinutes : Integer;
  dSeconds : Integer;
begin
  dHours   := Dur div 3600;
  Dec(Dur,dHours*3600);
  dMinutes := Dur div 60;
  Dec(Dur,dMinutes*60);
  dSeconds := Dur;

  If dHours > 0 then
    Result := IntToStr(dHours)  +'h '+IntToStr(dMinutes)+'m' else
    Result := IntToStr(dMinutes)+'m '+IntToStr(dSeconds)+'s';
end;

(*
function get_JSON(sURL : String{$IFDEF LOCALTRACE}; ThreadID : Integer{$ENDIF}) : String;
var
  lHTTP           : TIdHTTP;
  //Source,
  ResponseContent : TStringStream;
  //GZip            : TIdCompressorZLib;

begin
  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'get_JSON (before)');{$ENDIF}
  lHTTP := TIdHTTP.Create(nil);
  //GZip  := TIdCompressorZLib.Create;

  lHTTP.Request.ContentType    := 'text/xml';
  lHTTP.Request.Accept         := '*/*';
  lHTTP.Request.AcceptEncoding := 'gzip';
  lHTTP.Request.Connection     := 'Keep-Alive';
  lHTTP.Request.Method         := Id_HTTPMethodGet;
  lHTTP.Request.UserAgent      := URLIdentifier;
  //lHTTP.Compressor             := GZip;
  //Source := TStringStream.Create(sRPCRequest);
  ResponseContent := TStringStream.Create('');
  try
    try
      {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'get_JSON: HTTP.Get');{$ENDIF}
      lHTTP.Get(sURL, ResponseContent);
      Result := ResponseContent.DataString;
    except
      {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'get_JSON: exception');{$ENDIF}
      Result := '';
    end;
  finally
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'get_JSON: free (before)');{$ENDIF}
    //GZip.Free;
    lHTTP.Free;
    //Source.Free;
    ResponseContent.Free;
    {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'get_JSON: free (after)');{$ENDIF}
  end;
  {$IFDEF LOCALTRACE}DebugMsgFT(scrapeLog+IntToStr(ThreadID)+scrapeLogExt,'get_JSON (after)');{$ENDIF}
end;
*)


end.