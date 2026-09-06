unit ofd_package;
{$mode delphiunicode}{$H+}

{ OFD 包 (ZIP 文件) 处理单元
  Phase 1: Full extraction with budget checks and cleanup.
  TODO: Replace with streaming ZIP reads when TZipFile API is available. }

interface

uses
  Classes, SysUtils, Math, Zipper, ofd_errors;

const
  cMaxZipEntries = 20000;
  cMaxSingleEntryBytes = 256 * 1024 * 1024; { 256 MiB }
  cMaxTotalUncompressedBytes = 2 * 1024 * 1024 * 1024; { 2 GiB }

type

  { OFD 包 }
  TOFDPackage = class
  private
    FFileName: String;
    FExtractDir: String;
    FEntries: TStringList;
    procedure ReadCentralDirectory;
    function FindEntryIndex(const AName: String): Integer;
    procedure CheckPathSecurity(const APath: String);
    procedure DeleteDir(const ADir: String);
    function GetExtractRootDir: String;
    procedure CleanupStaleExtractDirs(const ARoot: String);
    function ParseExtractOwner(const ADirName: String): Integer;
  public
    constructor Create;
    destructor Destroy; override;

    { 打开 OFD 文件，验证 ZIP 结构 }
    procedure Open(const AFileName: String);

    { Extract an entry lazily (on first read) so opening a large OFD does not
      decompress every image/font/XML up front. }
    procedure EnsureExtracted(const AInternalPath: String);

    { 关闭包 }
    procedure Close;

    { 是否已打开 }
    function IsOpen: Boolean;

    { 获取内部文件列表 }
    function GetEntries: TStringList;

    { 检查指定内部路径是否存在 }
    function HasEntry(const AInternalPath: String): Boolean;

    { 读取内部文件内容为 TBytes }
    function ReadAsBytes(const AInternalPath: String): TBytes;

    { 读取内部文件内容为 String (UTF-8) }
    function ReadAsString(const AInternalPath: String): String;

    { 读取内部文件内容为 TStream (调用者负责释放) }
    function OpenStream(const AInternalPath: String): TStream;

    { 验证是否为有效的 OFD 包 }
    class function IsValidOFD(const AFileName: String): Boolean;

    { 获取 OFD 外部文件路径 }
    property FileName: String read FFileName;

    { 当前（或最近一次）解包目录，含唯一化后缀；未打开时为空。
      公开用于测试同一进程内连续打开两个包时目录名互不冲突。 }
    property ExtractDir: String read FExtractDir;
  end;

implementation

{ Process-wide sequence number making extract dir names unique even when two
  packages open within the same GetTickCount tick (GetTickCount resolution is
  ~1ms on some platforms, so PID+tick alone can collide). }
var
  ExtractDirSeq: Integer = 0;

{ TOFDPackage }

constructor TOFDPackage.Create;
begin
  inherited Create;
  FEntries := TStringList.Create;
  FFileName := '';
  FExtractDir := '';
end;

destructor TOFDPackage.Destroy;
begin
  if IsOpen then
    Close;
  FEntries.Free;
  inherited Destroy;
end;

procedure TOFDPackage.DeleteDir(const ADir: String);
var
  SR: TSearchRec;
  DPath, S: String;
begin
  DPath := IncludeTrailingPathDelimiter(ADir);
  if FindFirst(DPath + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Attr and faDirectory) <> 0 then
      begin
        if (SR.Name <> '.') and (SR.Name <> '..') then
          DeleteDir(DPath + SR.Name);
      end
      else
      begin
        S := DPath + SR.Name;
        try DeleteFile(S) except end;
      end;
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  try RemoveDir(ADir) except end;
end;

procedure TOFDPackage.Close;
begin
  if FExtractDir <> '' then
  begin
    DeleteDir(FExtractDir);
    FExtractDir := '';
  end;
  FFileName := '';
  FEntries.Clear;
end;

function TOFDPackage.GetExtractRootDir: String;
begin
  { Prefer project-local _tmp/ (working directory), fall back to system temp.
    System temp leaks on crash and pollutes the system disk. }
  Result := IncludeTrailingPathDelimiter(GetCurrentDir) + '_tmp';
  try
    if not DirectoryExists(Result) then
      ForceDirectories(Result);
    if not DirectoryExists(Result) then
      Result := GetTempDir;
  except
    Result := GetTempDir;
  end;
end;

function TOFDPackage.ParseExtractOwner(const ADirName: String): Integer;
var
  Sub, OwnerStr: String;
  UnderscorePos: Integer;
begin
  Result := -1;  { Legacy format without PID }
  if Pos('ofd_extract_', ADirName) <> 1 then
    Exit;
  Sub := Copy(ADirName, Length('ofd_extract_') + 1, MaxInt);
  UnderscorePos := Pos('_', Sub);
  if UnderscorePos = 0 then
    Exit;
  OwnerStr := Copy(Sub, 1, UnderscorePos - 1);
  if not TryStrToInt(OwnerStr, Result) then
    Result := -1;
end;

procedure TOFDPackage.CleanupStaleExtractDirs(const ARoot: String);
var
  SR: TSearchRec;
  DirPath: String;
begin
  { Delete ofd_extract_* dirs not owned by the current process.
    These are leftovers from crashed runs. Keep current-process dirs:
    another TOFDPackage instance in the same process may be using them. }
  if FindFirst(IncludeTrailingPathDelimiter(ARoot) + 'ofd_extract_*', faDirectory, SR) = 0 then
  begin
    repeat
      DirPath := IncludeTrailingPathDelimiter(ARoot) + SR.Name;
      if (ParseExtractOwner(SR.Name) <> Integer(GetProcessID)) then
        DeleteDir(DirPath);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
end;

procedure TOFDPackage.CheckPathSecurity(const APath: String);
var
  LPath: String;
begin
  if APath = '' then
    raise EOFDPathSecurityError.CreateFmt(
      '安全错误: 空路径 (路径: %s)', [APath]);

  { OFD 规范中 /Document.xml 表示包根路径，需要去掉前导分隔符 }
  LPath := APath;
  while (Length(LPath) > 0) and ((LPath[1] = '/') or (LPath[1] = '\')) do
    LPath := Copy(LPath, 2, MaxInt);

  if LPath = '' then
    raise EOFDPathSecurityError.CreateFmt(
      '安全错误: 空路径 (路径: %s)', [APath]);

  { URL decode to catch %2e%2e etc. }
  LPath := LowerCase(LPath);
  LPath := StringReplace(LPath, '%2e', '.', [rfReplaceAll]);
  LPath := StringReplace(LPath, '%5c', '\', [rfReplaceAll]);
  LPath := StringReplace(LPath, '%2f', '/', [rfReplaceAll]);

  if (Pos('../', LPath) > 0) or (Pos('..\', LPath) > 0) then
    raise EOFDPathSecurityError.CreateFmt(
      '安全错误: 路径穿越尝试 (路径: %s)', [APath]);

  if (LPath = '..') or (LPath = '..\') or (LPath = '../') then
    raise EOFDPathSecurityError.CreateFmt(
      '安全错误: 路径穿越尝试 (路径: %s)', [APath]);

  { Check for .. at the end of segments }
  if (Pos('/..', LPath) > 0) or (Pos('\..', LPath) > 0) then
    raise EOFDPathSecurityError.CreateFmt(
      '安全错误: 路径穿越尝试 (路径: %s)', [APath]);

  { Check for null bytes }
  if Pos(#0, APath) > 0 then
    raise EOFDPathSecurityError.CreateFmt(
      '安全错误: 路径包含空字节 (路径: %s)', [APath]);
end;

procedure TOFDPackage.ReadCentralDirectory;
var
  UnZipper: TUnZipper;
  I: Integer;
  EntryName: String;
  ExtractRoot: String;
  TotalUncompressed: Int64;
begin
  FEntries.Clear;

  if not FileExists(FFileName) then
    Exit;

  { Phase 1: Create temp extraction directory in project _tmp/, cleanup stale }
  ExtractRoot := GetExtractRootDir;
  CleanupStaleExtractDirs(ExtractRoot);
  FExtractDir := IncludeTrailingPathDelimiter(ExtractRoot) + 'ofd_extract_' +
    IntToStr(GetProcessID) + '_' + IntToStr(GetTickCount) + '_' +
    IntToStr(InterLockedIncrement(ExtractDirSeq));
  ForceDirectories(FExtractDir);

  UnZipper := TUnZipper.Create;
  try
    try
      UnZipper.FileName := FFileName;
      UnZipper.OutputPath := FExtractDir;
      { Read the central directory to populate Entries (no extraction). }
      UnZipper.Examine;

      { Validate all entry paths BEFORE extraction to prevent Zip Slip }
      for I := 0 to UnZipper.Entries.Count - 1 do
      begin
        EntryName := UnZipper.Entries[I].ArchiveFileName;
        try
          CheckPathSecurity(EntryName);
        except
          on E: EOFDPathSecurityError do
            raise EOFDPathSecurityError.CreateFmt(
              '安全错误: ZIP 条目路径穿越 (条目: %s)', [EntryName]);
        end;
      end;

      { Per-entry and total uncompressed budget checks (Zip Bomb protection)
        BEFORE any extraction, fail-closed. }
      TotalUncompressed := 0;
      for I := 0 to UnZipper.Entries.Count - 1 do
      begin
        if UnZipper.Entries[I].Size > cMaxSingleEntryBytes then
          raise EOFDPackageError.CreateFmt(
            'ZIP 单条目过大，可能存在 Zip Bomb 攻击 (条目: %s, 大小: %d 字节, 上限: %d 字节)',
            [UnZipper.Entries[I].ArchiveFileName,
             UnZipper.Entries[I].Size, cMaxSingleEntryBytes]);
        Inc(TotalUncompressed, UnZipper.Entries[I].Size);
      end;
      if TotalUncompressed > cMaxTotalUncompressedBytes then
        raise EOFDPackageError.CreateFmt(
          'ZIP 总解压体积过大，可能存在 Zip Bomb 攻击 (总计: %d 字节, 上限: %d 字节)',
          [TotalUncompressed, cMaxTotalUncompressedBytes]);

      { Phase 2: Do NOT extract every entry up front — that decompresses all
        images/fonts/XML on open and makes large OFD files (and the render
        worker's second copy) slow to open. Entries are extracted lazily in
        OpenStream (EnsureExtracted) only when actually read. }
      for I := 0 to UnZipper.Entries.Count - 1 do
      begin
        EntryName := UnZipper.Entries[I].ArchiveFileName;
        if (Length(EntryName) > 0) and (EntryName[Length(EntryName)] <> '/') then
          FEntries.Add(EntryName);
      end;
    except
      { Exception-safe: remove extract dir created above, then re-raise }
      DeleteDir(FExtractDir);
      FExtractDir := '';
      raise;
    end;
  finally
    UnZipper.Free;
  end;

  { Phase 1: Entry count budget check }
  if FEntries.Count > cMaxZipEntries then
    raise EOFDPackageError.CreateFmt(
      'ZIP 条目过多，可能存在 Zip Bomb 攻击 (条目数: %d, 上限: %d)',
      [FEntries.Count, cMaxZipEntries]);
end;

{ Extract a single archive entry (and its parent directories) to the temp dir
  on first access. Keeps open fast: only the entries that are actually read are
  decompressed. }
procedure TOFDPackage.EnsureExtracted(const AInternalPath: String);
var
  UnZipper: TUnZipper;
  FileList: TStringList;
begin
  if not IsOpen then Exit;
  if FileExists(StringReplace(
    IncludeTrailingPathDelimiter(FExtractDir) + AInternalPath,
    '/', PathDelim, [rfReplaceAll])) then Exit;

  FileList := TStringList.Create;
  UnZipper := nil;
  try
    FileList.Add(AInternalPath);
    UnZipper := TUnZipper.Create;
    UnZipper.FileName := FFileName;
    UnZipper.OutputPath := FExtractDir;
    try
      UnZipper.UnZipFiles(FileList);
    except
      on E: Exception do
        raise EOFDPackageError.CreateFmt(
          '解压条目失败: %s (文件: %s, 错误: %s)', [AInternalPath, FFileName, E.Message]);
    end;
  finally
    FileList.Free;
    UnZipper.Free;
  end;
end;

procedure TOFDPackage.Open(const AFileName: String);
var
  LFileName: String;
begin
  LFileName := ExpandFileName(AFileName);

  if not FileExists(LFileName) then
    raise EOFDPackageError.CreateFmt(
      'OFD 文件不存在: %s', [LFileName]);

  { 关闭之前的包 }
  if IsOpen then
    Close;

  FFileName := LFileName;

  try
    { 读取 ZIP 中央目录 }
    ReadCentralDirectory;

    { 验证 OFD 基本结构 }
    if not HasEntry('OFD.xml') then
      raise EOFDPackageError.CreateFmt(
        '无效的 OFD 文件: 缺少 OFD.xml (文件路径: %s)', [FFileName]);
  except
    { Exception-safe: never leave extract dir behind on failed open }
    Close;
    raise;
  end;
end;

function TOFDPackage.IsOpen: Boolean;
begin
  Result := FFileName <> '';
end;

function TOFDPackage.GetEntries: TStringList;
begin
  Result := FEntries;
end;

function TOFDPackage.FindEntryIndex(const AName: String): Integer;
var
  I: Integer;
  EntryName, SearchName: String;
begin
  SearchName := AName;
  { Remove trailing slash if present }
  if (Length(SearchName) > 0) and (SearchName[Length(SearchName)] = '/') then
    SearchName := Copy(SearchName, 1, Length(SearchName) - 1);
  
  for I := 0 to FEntries.Count - 1 do
  begin
    EntryName := FEntries[I];
    { Remove trailing slash from entry name }
    if (Length(EntryName) > 0) and (EntryName[Length(EntryName)] = '/') then
      EntryName := Copy(EntryName, 1, Length(EntryName) - 1);
    
    if CompareText(EntryName, SearchName) = 0 then
      Exit(I);
  end;
  Result := -1;
end;

function TOFDPackage.HasEntry(const AInternalPath: String): Boolean;
var
  Normalized: String;
begin
  if not IsOpen then
    raise EOFDPackageError.CreateFmt(
      '无法访问条目: 包未打开 (文件: %s)', [FFileName]);
  CheckPathSecurity(AInternalPath);
  { Strip leading separators for OFD root-relative paths }
  Normalized := AInternalPath;
  while (Length(Normalized) > 0) and ((Normalized[1] = '/') or (Normalized[1] = '\')) do
    Normalized := Copy(Normalized, 2, MaxInt);
  Result := FindEntryIndex(Normalized) >= 0;
end;

function TOFDPackage.OpenStream(const AInternalPath: String): TStream;
var
  EntryIdx: Integer;
  FilePath: String;
  DirPath: String;
  Normalized: String;
  ResolvedFile, ResolvedRoot: String;
begin
  if not IsOpen then
    raise EOFDPackageError.CreateFmt(
      '无法访问条目: 包未打开 (文件: %s)', [FFileName]);
  CheckPathSecurity(AInternalPath);

  { Strip leading separators for OFD root-relative paths }
  Normalized := AInternalPath;
  while (Length(Normalized) > 0) and ((Normalized[1] = '/') or (Normalized[1] = '\')) do
    Normalized := Copy(Normalized, 2, MaxInt);

  EntryIdx := FindEntryIndex(Normalized);
  if EntryIdx < 0 then
    raise EOFDPackageError.CreateFmt(
      '内部文件不存在: %s (文件: %s)', [AInternalPath, FFileName]);

  { Lazy extraction: decompress this entry (and its dirs) on first read only. }
  EnsureExtracted(Normalized);

  { Cross-platform path joining }
  DirPath := IncludeTrailingPathDelimiter(FExtractDir);
  FilePath := DirPath + Normalized;
  { Normalize path separators for the platform }
  FilePath := StringReplace(FilePath, '/', PathDelim, [rfReplaceAll]);

  { 安全校验：确保解压后文件在临时目录内。使用 ExpandFileName 规范化路径，
    以捕获 '..' 段、符号链接等任何解析后逃逸出临时目录的情况。 }
  ResolvedFile := ExpandFileName(FilePath);
  ResolvedRoot := ExpandFileName(FExtractDir);
  if not ((Length(ResolvedFile) > Length(ResolvedRoot)) and
          (CompareText(Copy(ResolvedFile, 1, Length(ResolvedRoot)), ResolvedRoot) = 0)) then
    raise EOFDPathSecurityError.CreateFmt(
      '安全错误: 解压路径逃逸 (路径: %s, 临时目录: %s)',
      [FilePath, FExtractDir]);

  Result := TFileStream.Create(FilePath, fmOpenRead or fmShareDenyWrite);
end;

function TOFDPackage.ReadAsBytes(const AInternalPath: String): TBytes;
var
  S: TStream;
begin
  Result := nil;
  S := OpenStream(AInternalPath);
  try
    SetLength(Result, S.Size);
    if S.Size > 0 then
      S.ReadBuffer(Result[0], S.Size);
  finally
    S.Free;
  end;
end;

function TOFDPackage.ReadAsString(const AInternalPath: String): String;
var
  Bytes: TBytes;
  Len, I: Integer;
  Encoding: TEncoding;
  HasHighBytes: Boolean;
  LooksLikeUTF8: Boolean;
  UTF8Data: UTF8String;
begin
  Bytes := ReadAsBytes(AInternalPath);
  Len := Length(Bytes);
  Result := '';
  if Len = 0 then Exit;

  { Strip UTF-8 BOM (EF BB BF) if present }
  if (Len >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
  begin
    if Len = 3 then Exit;
    System.Move(Bytes[3], Bytes[0], Len - 3);
    SetLength(Bytes, Len - 3);
    Len := Len - 3;
  end;

  { OFD spec requires UTF-8, but some files use GBK encoding.
    Detect: if bytes don't form valid UTF-8, fall back to GBK. }
  Encoding := TEncoding.UTF8;
  HasHighBytes := False;
  for I := 0 to Len - 1 do
  begin
    if Bytes[I] >= $80 then
    begin
      HasHighBytes := True;
      Break;
    end;
  end;

  if HasHighBytes then
  begin
    LooksLikeUTF8 := True;
    I := 0;
    while I < Len do
    begin
      if Bytes[I] < $80 then
      begin
        Inc(I);
        Continue;
      end;
      if (Bytes[I] and $E0) = $C0 then
      begin
        if (I + 1 >= Len) or ((Bytes[I + 1] and $C0) <> $80) then
        begin
          LooksLikeUTF8 := False;
          Break;
        end;
        Inc(I, 2);
      end
      else if (Bytes[I] and $F0) = $E0 then
      begin
        if (I + 2 >= Len) or ((Bytes[I + 1] and $C0) <> $80) or
           ((Bytes[I + 2] and $C0) <> $80) then
        begin
          LooksLikeUTF8 := False;
          Break;
        end;
        Inc(I, 3);
      end
      else if (Bytes[I] and $F8) = $F0 then
      begin
        if (I + 3 >= Len) or ((Bytes[I + 1] and $C0) <> $80) or
           ((Bytes[I + 2] and $C0) <> $80) or ((Bytes[I + 3] and $C0) <> $80) then
        begin
          LooksLikeUTF8 := False;
          Break;
        end;
        Inc(I, 4);
      end
      else
      begin
        LooksLikeUTF8 := False;
        Break;
      end;
    end;

   if not LooksLikeUTF8 then
    begin
      Encoding := TEncoding.GetEncoding(936); { GBK/GB2312 }
    end;
  end;

  { Decode to UnicodeString }
  if Encoding = TEncoding.UTF8 then
  begin
    SetLength(UTF8Data, Len);
    if Len > 0 then
      Move(Bytes[0], UTF8Data[1], Len);
    Result := UTF8Decode(UTF8Data);
  end
  else
  begin
    { GetEncoding(936) 每次创建新实例，GetString 抛异常时也要释放 }
    try
      Result := Encoding.GetString(Bytes, 0, Len);
    finally
      if (Encoding <> TEncoding.UTF8) and (Encoding <> TEncoding.ANSI) and
         (Encoding <> TEncoding.ASCII) and (Encoding <> TEncoding.BigEndianUnicode) and
         (Encoding <> TEncoding.Unicode) then
        Encoding.Free;
    end;
  end;
end;

class function TOFDPackage.IsValidOFD(const AFileName: String): Boolean;
var
  Pkg: TOFDPackage;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  Pkg := TOFDPackage.Create;
  try
    try
      Pkg.Open(AFileName);
      Result := True;
    except
      Result := False;
    end;
  finally
    Pkg.Free;
  end;
end;

end.
