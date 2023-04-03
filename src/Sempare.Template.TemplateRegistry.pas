(*%*************************************************************************************************
 *                 ___                                                                              *
 *                / __|  ___   _ __    _ __   __ _   _ _   ___                                      *
 *                \__ \ / -_) | '  \  | '_ \ / _` | | '_| / -_)                                     *
 *                |___/ \___| |_|_|_| | .__/ \__,_| |_|   \___|                                     *
 *                                    |_|                                                           *
 ****************************************************************************************************
 *                                                                                                  *
 *                          Sempare Template Engine                                                 *
 *                                                                                                  *
 *                                                                                                  *
 *         https://github.com/sempare/sempare-delphi-template-engine                                *
 ****************************************************************************************************
 *                                                                                                  *
 * Copyright (c) 2019-2023 Sempare Limited                                                          *
 *                                                                                                  *
 * Contact: info@sempare.ltd                                                                        *
 *                                                                                                  *
 * Licensed under the GPL Version 3.0 or the Sempare Commercial License                             *
 * You may not use this file except in compliance with one of these Licenses.                       *
 * You may obtain a copy of the Licenses at                                                         *
 *                                                                                                  *
 * https://www.gnu.org/licenses/gpl-3.0.en.html                                                     *
 * https://github.com/sempare/sempare-delphi-template-engine/blob/master/docs/commercial.license.md *
 *                                                                                                  *
 * Unless required by applicable law or agreed to in writing, software                              *
 * distributed under the Licenses is distributed on an "AS IS" BASIS,                               *
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.                         *
 * See the License for the specific language governing permissions and                              *
 * limitations under the License.                                                                   *
 *                                                                                                  *
 *************************************************************************************************%*)
unit Sempare.Template.TemplateRegistry;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  System.SyncObjs,
  Sempare.Template.Context,
  Sempare.Template.AST;

// NOTE: refresh is done simply by using a thread periodically. a more optimal approach could be to use
// file system events, but for development, this should be ok.

type
  ETemplateRefreshTooFrequent = class(Exception)
  public
    constructor Create;
  end;

  ETemplateNotResolved = class(Exception)
  public
    constructor Create(const ATemplateName: string);
  end;

  IRefreshableTemplate = interface(ITemplate)
    ['{AC4008EA-336F-4DCB-B6E6-E11034DF5ACF}']
    procedure Refresh;
  end;

  TAbstractProxyTemplate = class abstract(TInterfacedObject, ITemplate)
  strict protected
    FTemplate: ITemplate;
  public
    constructor Create(const ATemplate: ITemplate);
    function GetItem(const AOffset: integer): IStmt;
    function GetCount: integer;
    function GetLastItem: IStmt;
    procedure Optimise;
    procedure Accept(const AVisitor: ITemplateVisitor);
    function GetFilename: string;
    procedure SetFilename(const AFilename: string);
    function GetLine: integer;
    procedure SetLine(const Aline: integer);
    function GetPos: integer;
    procedure SetPos(const Apos: integer);
  end;

  TResourceTemplate = class(TAbstractProxyTemplate)
  public
    constructor Create(const AContext: ITemplateContext; const AName: string);
  end;

  TFileTemplate = class(TAbstractProxyTemplate, IRefreshableTemplate)
  strict private
    FContext: ITemplateContext;
    FModifiedAt: TDateTime;
    procedure Load(const AFilename: string; const ATime: TDateTime);
  public
    constructor Create(const AContext: ITemplateContext; const AFilename: string);
    procedure Refresh;
  end;

  TTemplateLoadStrategy = (tlsLoadResource, tlsLoadFile, tlsLoadCustom);
  TTemplateNameContextResolver = reference to function: TArray<string>;
  TTemplateNameResolver = reference to function(const AName: string; const AContext: TArray<string>): string;
  TTempateLogException = reference to procedure(const AException: Exception);

  TTemplateRegistry = class
  strict private
    class var FTemplateRegistry: TTemplateRegistry;
    class constructor Create;
    class destructor Destroy;
  strict private
    FLock: TCriticalSection;
    FTemplates: TDictionary<string, ITemplate>;
    FContext: ITemplateContext;
    FLoadStrategy: TArray<TTemplateLoadStrategy>;
    FResourceNameResolver: TTemplateNameResolver;
    FFileNameResolver: TTemplateNameResolver;
    FTemplateRootFolder: string;
    FTemplateFileExt: string;
    FRefreshIntervalS: integer;
    FShutdown: TEvent;
    FThreadDone: TEvent;
    FThread: TThread;
    FAutomaticRefresh: boolean;
    FCustomTemplateLoader: TTemplateResolver;
    FNameContextResolver: TTemplateNameContextResolver;
    FLogException: TTempateLogException;

    procedure Refresh;

    procedure SetRefreshIntervalS(const Value: integer);
    procedure SetAutomaticRefresh(const Value: boolean);
    procedure SetLoadStrategy(const Value: TArray<TTemplateLoadStrategy>);
    procedure SetTemplateFileExt(const Value: string);
    procedure LogException(const AException: Exception);
  public
    constructor Create();
    destructor Destroy; override;

    function GetTemplate(const ATemplateName: string): ITemplate; overload;

    procedure Eval(const AOutputStream: TStream; const ATemplate: ITemplate); overload;
    procedure Eval<T>(const AOutputStream: TStream; const ATemplate: ITemplate; const AData: T); overload;
    function Eval<T>(const ATemplate: ITemplate; const AData: T): string; overload;
    function Eval(const ATemplate: ITemplate): string; overload;

    procedure Eval(const AOutputStream: TStream; const ATemplateName: string); overload;
    procedure Eval<T>(const AOutputStream: TStream; const ATemplateName: string; const AData: T); overload;
    function Eval<T>(const ATemplateName: string; const AData: T): string; overload;
    function Eval(const ATemplateName: string): string; overload;

    class property Instance: TTemplateRegistry read FTemplateRegistry;

    property Context: ITemplateContext read FContext;
    property ResourceNameResolver: TTemplateNameResolver read FResourceNameResolver write FResourceNameResolver;
    property FileNameResolver: TTemplateNameResolver read FFileNameResolver write FFileNameResolver;
    property TemplateRootFolder: string read FTemplateRootFolder write FTemplateRootFolder;
    property TemplateFileExt: string read FTemplateFileExt write SetTemplateFileExt;
    property LoadStrategy: TArray<TTemplateLoadStrategy> read FLoadStrategy write SetLoadStrategy;
    property RefreshIntervalS: integer read FRefreshIntervalS write SetRefreshIntervalS;
    property AutomaticRefresh: boolean read FAutomaticRefresh write SetAutomaticRefresh;
    property CustomTemplateLoader: TTemplateResolver read FCustomTemplateLoader write FCustomTemplateLoader;
    property NameContextResolver: TTemplateNameContextResolver read FNameContextResolver write FNameContextResolver;
    property ExceptionLogger: TTempateLogException read FLogException write FLogException;

  end;

implementation

uses
  System.Net.UrlClient,
  System.Net.HttpClient,
  Sempare.Template.ResourceStrings,
  Sempare.Template,
  System.IOUtils,
  System.DateUtils;

{ TTemplateRegistry }

constructor TTemplateRegistry.Create;
var
  LPath: string;
begin
  FShutdown := TEvent.Create;
  FThreadDone := TEvent.Create;

  FLock := TCriticalSection.Create;
  FTemplates := TDictionary<string, ITemplate>.Create;
  FContext := Template.Context([eoEmbedException]);

  TemplateFileExt := '.tpl';

  FResourceNameResolver := function(const AName: string; const AContext: TArray<string>): string
    begin
      exit(AName.ToLower.Replace('.', '_', [rfReplaceAll]));
    end;

  FFileNameResolver := function(const AName: string; const AContext: TArray<string>): string
    begin
      exit(TPath.Combine(TTemplateRegistry.Instance.TemplateRootFolder, AName));
    end;

  FTemplateRootFolder := TPath.Combine(TPath.GetDirectoryName(paramstr(0)), 'templates');
{$IFDEF DEBUG}
  if not TDirectory.Exists(FTemplateRootFolder) then
  begin
    LPath := TPath.GetFullPath(TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetDirectoryName(paramstr(0)), '..'), '..'), 'templates'));
    if TDirectory.Exists(LPath) then
    begin
      FTemplateRootFolder := LPath;
    end;
  end;
{$ENDIF}
  FContext.Variable['CopyrightYear'] := YearOf(Now);

  FContext.TemplateResolver := function(const AContext: ITemplateContext; const AName: string): ITemplate
    begin
      exit(GetTemplate(AName));
    end;

{$IFDEF DEBUG}
  FLoadStrategy := [tlsLoadFile, tlsLoadResource];
  FRefreshIntervalS := 5;
  AutomaticRefresh := true;
{$ELSE}
  FRefreshIntervalS := 10;
  FLoadStrategy := [tlsLoadResource];
  AutomaticRefresh := false;
{$ENDIF}
end;

class constructor TTemplateRegistry.Create;
begin
  FTemplateRegistry := TTemplateRegistry.Create;
end;

destructor TTemplateRegistry.Destroy;
begin
  FShutdown.SetEvent;
  FThreadDone.WaitFor();
  FThreadDone.Free;
  FShutdown.Free;
  FLock.Free;
  FTemplates.Free;
  inherited;
end;

class destructor TTemplateRegistry.Destroy;
begin
  FTemplateRegistry.Free;
end;

function TTemplateRegistry.GetTemplate(const ATemplateName: string): ITemplate;

var
  LNameContext: TArray<string>;

  function LoadFromRegistry(out ATemplate: ITemplate): boolean;
  var
    LName: string;
    LExt: string;
  begin
    ATemplate := nil;
    for LExt in [FTemplateFileExt, ''] do
    begin
      LName := FResourceNameResolver(ATemplateName + LExt, LNameContext);
      try
        ATemplate := TResourceTemplate.Create(FContext, LName);
        exit(true);
      except
        on e: Exception do
          LogException(e);
      end;
    end;
    exit(false);
  end;

  function LoadFromFile(out ATemplate: ITemplate): boolean;
  var
    LName: string;
    LExt: string;
  begin
    result := false;
    ATemplate := nil;
    for LExt in [FTemplateFileExt, ''] do
    begin
      LName := FFileNameResolver(ATemplateName + FTemplateFileExt, LNameContext);
      if TFile.Exists(LName) then
      begin
        try
          ATemplate := TFileTemplate.Create(FContext, LName);
          exit(true);
        except
          on e: Exception do
            LogException(e);
        end;
      end;
    end;
  end;

  function LoadFromCustom(out ATemplate: ITemplate): boolean;
  var
    LName: string;
    LExt: string;
  begin
    result := false;
    ATemplate := nil;
    if not assigned(FCustomTemplateLoader) then
      exit;

    for LExt in [FTemplateFileExt, ''] do
    begin
      try
        LName := FResourceNameResolver(ATemplateName + LExt, LNameContext);
        ATemplate := FCustomTemplateLoader(FContext, LName + FTemplateFileExt);
        exit(true);
      except
        on e: Exception do
          LogException(e);
      end;
    end;
  end;

var
  LLoadStrategy: TTemplateLoadStrategy;

begin
  FLock.Acquire;
  try
    if FTemplates.TryGetValue(ATemplateName, result) then
      exit;
  finally
    FLock.Release;
  end;
  result := nil;
  if assigned(FNameContextResolver) then
    LNameContext := FNameContextResolver
  else
    LNameContext := nil;
  for LLoadStrategy in TTemplateRegistry.Instance.LoadStrategy do
  begin
    case LLoadStrategy of
      tlsLoadResource:
        if LoadFromRegistry(result) then
          break;
      tlsLoadFile:
        if LoadFromFile(result) then
          break;
      tlsLoadCustom:
        if LoadFromCustom(result) then
          break;
    end;
  end;
  if not assigned(result) then
    raise ETemplateNotResolved.Create(ATemplateName);
  FLock.Acquire;
  try
    FTemplates.Add(ATemplateName, result);
  finally
    FLock.Release;
  end;
end;

procedure TTemplateRegistry.LogException(const AException: Exception);
begin
  if assigned(FLogException) then
    FLogException(AException);
end;

function TTemplateRegistry.Eval(const ATemplateName: string): string;
var
  LTemplate: ITemplate;
begin
  LTemplate := GetTemplate(ATemplateName);
  exit(Template.Eval(FContext, LTemplate));
end;

function TTemplateRegistry.Eval<T>(const ATemplate: ITemplate; const AData: T): string;
begin

end;

procedure TTemplateRegistry.Eval<T>(const AOutputStream: TStream; const ATemplate: ITemplate; const AData: T);
begin

end;

procedure TTemplateRegistry.Eval(const AOutputStream: TStream; const ATemplateName: string);
var
  LTemplate: ITemplate;
begin
  LTemplate := GetTemplate(ATemplateName);
  Template.Eval(FContext, LTemplate, AOutputStream);
end;

procedure TTemplateRegistry.Eval<T>(const AOutputStream: TStream; const ATemplateName: string; const AData: T);
var
  LTemplate: ITemplate;
begin
  LTemplate := GetTemplate(ATemplateName);
  Template.Eval(FContext, LTemplate, AData, AOutputStream);
end;

procedure TTemplateRegistry.Eval(const AOutputStream: TStream; const ATemplate: ITemplate);
begin

end;

function TTemplateRegistry.Eval(const ATemplate: ITemplate): string;
begin

end;

function TTemplateRegistry.Eval<T>(const ATemplateName: string; const AData: T): string;
var
  LTemplate: ITemplate;
begin
  LTemplate := GetTemplate(ATemplateName);
  exit(Template.Eval(FContext, LTemplate, AData));
end;

procedure TTemplateRegistry.Refresh;
var
  LRefreshable: IRefreshableTemplate;
  LTemplate: ITemplate;
begin
  FLock.Acquire;
  try
    for LTemplate in FTemplates.Values do
    begin
      if supports(LTemplate, IRefreshableTemplate, LRefreshable) then
      begin
        LRefreshable.Refresh;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TTemplateRegistry.SetAutomaticRefresh(const Value: boolean);
begin
  if FAutomaticRefresh = Value then
    exit;

  FAutomaticRefresh := Value;
  if Value then
  begin
    FThread := TThread.CreateAnonymousThread(
      procedure
      begin
        while true do
        begin
          case FShutdown.WaitFor(TTemplateRegistry.Instance.RefreshIntervalS * 1000) of
            wrSignaled:
              break;
            wrTimeout:
              ;
          end;
          Refresh;
        end;
        FThreadDone.SetEvent;
      end);
{$IFDEF DEBUG}
    TThread.NameThreadForDebugging('TTemplateRegistry.RefreshThread', FThread.ThreadID);
{$ENDIF}
    FThread.Start;
  end
  else if FThread <> nil then
  begin
    FShutdown.SetEvent;
    FThreadDone.WaitFor();
  end;
end;

procedure TTemplateRegistry.SetLoadStrategy(const Value: TArray<TTemplateLoadStrategy>);
begin
  FLoadStrategy := Value;
  if (length(FLoadStrategy) = 1) and (FLoadStrategy[0] = tlsLoadResource) then
    AutomaticRefresh := false;
end;

procedure TTemplateRegistry.SetRefreshIntervalS(const Value: integer);
begin
  if Value < 5 then
    raise ETemplateRefreshTooFrequent.Create();
  FRefreshIntervalS := Value;
end;

procedure TTemplateRegistry.SetTemplateFileExt(const Value: string);
begin
  FTemplateFileExt := Value;
  if not FTemplateFileExt.StartsWith('.') then
    FTemplateFileExt := '.' + FTemplateFileExt;
end;

{ TAbstractProxyTemplate }

procedure TAbstractProxyTemplate.Accept(const AVisitor: ITemplateVisitor);
begin
  FTemplate.Accept(AVisitor);
end;

constructor TAbstractProxyTemplate.Create(const ATemplate: ITemplate);
begin
  FTemplate := ATemplate;
end;

function TAbstractProxyTemplate.GetCount: integer;
begin
  exit(FTemplate.Count);
end;

function TAbstractProxyTemplate.GetFilename: string;
begin
  exit(FTemplate.FileName);
end;

function TAbstractProxyTemplate.GetItem(const AOffset: integer): IStmt;
begin
  exit(FTemplate.GetItem(AOffset));
end;

function TAbstractProxyTemplate.GetLastItem: IStmt;
begin
  exit(FTemplate.GetLastItem);
end;

function TAbstractProxyTemplate.GetLine: integer;
begin
  exit(FTemplate.line);
end;

function TAbstractProxyTemplate.GetPos: integer;
begin
  exit(FTemplate.pos);
end;

procedure TAbstractProxyTemplate.Optimise;
begin
  FTemplate.Optimise;
end;

procedure TAbstractProxyTemplate.SetFilename(const AFilename: string);
begin
  FTemplate.FileName := AFilename;
end;

procedure TAbstractProxyTemplate.SetLine(const Aline: integer);
begin
  FTemplate.line := Aline;
end;

procedure TAbstractProxyTemplate.SetPos(const Apos: integer);
begin
  FTemplate.pos := Apos;
end;

{ TResourceTemplate }

constructor TResourceTemplate.Create(const AContext: ITemplateContext; const AName: string);
var
  LStream: TStream;
  LTemplate: ITemplate;
begin
  LStream := TResourceStream.Create(HInstance, AName, RT_RCDATA);
  LTemplate := Template.Parse(AContext, LStream);
  inherited Create(LTemplate);
  LTemplate.FileName := '[Resource(' + AName + ')]';
end;

{ TFileTemplate }

constructor TFileTemplate.Create(const AContext: ITemplateContext; const AFilename: string);
begin
  FContext := AContext;
  inherited Create(nil);
  Load(AFilename, TFile.GetLastWriteTime(AFilename));
end;

procedure TFileTemplate.Load(const AFilename: string; const ATime: TDateTime);
var
  LStream: TStream;
  LTemplate: ITemplate;
begin
  if FModifiedAt = ATime then
    exit;
  LStream := TBufferedFileStream.Create(AFilename, fmOpenRead or fmShareDenyNone);
  LTemplate := Template.Parse(FContext, LStream);
  inherited Create(LTemplate);
  LTemplate.FileName := AFilename;
  FModifiedAt := ATime;
end;

procedure TFileTemplate.Refresh;
begin
  Load(FTemplate.FileName, TFile.GetLastWriteTime(FTemplate.FileName));
end;

{ ETemplateNotResolved }

constructor ETemplateNotResolved.Create(const ATemplateName: string);
begin
  inherited CreateResFmt(@STemplateNotFound, [ATemplateName]);
end;

{ ETemplateRefreshTooFrequent }

constructor ETemplateRefreshTooFrequent.Create;
begin
  inherited CreateRes(@SRefreshTooFrequent);
end;

end.
