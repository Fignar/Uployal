{~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~}
{                                                                              }
{                                 �������                                      }
{                                                                              }
{                       Copyright (c) 2025 ������� ����                        }
{                                12.04.2025                                    }
{                                                                              }
{   Modified based on Gemini discussion (27.10.2025) - TResult<T> + Detail     }
{                                                                              }
{~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~}

unit AppUtils;

interface

uses Windows, Forms, Controls, SysUtils;

type
  // 1. TResult - ��� ��������, ������������ ������ ������
  TResult          = record
  strict private
    FSuccess       : boolean;
    FMessage       : string;
    FErrorCode     :  integer;
  public
    class function Ok(const AMsg: string = ''): TResult; static;
    class function Fail(const AMsg: string; const ACode: integer = 0): TResult; static;
    function       IsOk: boolean; inline;
    function       IsFail: boolean; inline;
    property       Success: boolean read FSuccess;
    property       Message: string read FMessage;
    property       ErrorCode: integer read FErrorCode;
  end;

  // 2. TResult<T> - ��� ��������, ������������ ������ (� ErrorDetail)
  TResult<T>       = record
  strict private
    FSuccess       : boolean;
    FValue         : T;
    FError         : string;       // <-- ������ ������/�������� ���������
    FErrorCode     : integer;
    FErrorDetail   : string; // <-- ��������� ���������
  public
    class function Ok(const AValue: T): TResult<T>; static;
    // ��������: �������� ADetailMessage
    class function Fail(const AError: string; const AErrorCode: integer; const ADetailMessage: string = ''): TResult<T>; static;
    function       IsOk: boolean; inline;
    function       IsFail: boolean; inline;
    function       OrDefault(const ADefault: T): T; inline;
    property       Success: boolean read FSuccess;
    property       Value: T read FValue;
    property       Error: string read FError; // ������ ������
    property       ErrorCode: integer read FErrorCode;
    property       ErrorDetail: string read FErrorDetail; // ������
  end;

  // 3. TApiResult - ��� ������� API
  TApiResult       = record
  strict private
    FSuccess       : boolean;
    FValue         : string;   // �������� JSON-�����
    FStatusCode    : integer; // HTTP ������ ��� (���� ���������, ����� 0 ��� ���������)
    FStatusValue   : string; // ������ ����� ������� (�� TResult.Error)
    FError         : string;   // ��������� ��������� �� ������ (�� TResult.ErrorDetail)
    FErrorCode     : integer; // ������-��� ������ (����� ��������� � StatusCode)
    FErrorType     : string; // ��� ������ ('NETWORK_ERROR', 'CLIENT_GET_ERROR', etc.)
    function        GetJson: string; // ��������� ����� ��� �������� ToJson
  public
    class function Ok(const AValueJson: string): TApiResult; static;
    // ��������: Fail ��������� ������ ������ � ��������� ��������� ��������
    class function Fail(const AStatusValue: string; const AErrorCode: integer; const AErrorType: string; const ADetailError: string = ''): TApiResult; static;
    function       IsOk: boolean; inline;
    function       IsFail: boolean; inline;
    property       Success: boolean read FSuccess;
    property       Value: string read FValue; // ������ � ��������� JSON
    property       StatusCode: integer read FStatusCode;
    property       StatusValue: string read FStatusValue; // ������ � ������� �������
    property       Error: string read FError; // ������ � ���������� ���������
    property       ErrorCode: integer read FErrorCode;
    property       ErrorType: string read FErrorType;
    property       ToJson: string read GetJson; // �������� ���������� JSON
  end;

function           FromClipboardExcel : TArray<TArray<string>>;
function           GetClipboardExcel  : TArray<TArray<string>>;
procedure          SetRussianKeyboardLayout;

implementation

uses Clipbrd, Table, xSuperObject; // �������� xSuperObject

// --- ���������� TResult ---
class function TResult.Ok(const AMsg: string): TResult;
begin
  Result.FSuccess := True;
  Result.FMessage := AMsg;
  Result.FErrorCode := 0;
end;

class function TResult.Fail(const AMsg: string; const ACode: integer): TResult;
begin
  Result.FSuccess := false;
  Result.FMessage := AMsg;
  Result.FErrorCode := ACode;
end;

function TResult.IsOk: boolean;
begin
  Result := FSuccess;
end;

function TResult.IsFail: boolean;
begin
  Result := not FSuccess;
end;

// --- ���������� TResult<T> ---
class function TResult<T>.Ok(const AValue: T): TResult<T>;
begin
  Result.FSuccess := True;
  Result.FValue := AValue;
  Result.FError := '';
  Result.FErrorCode := 0;
  Result.FErrorDetail := '';
end;

// ��������: ���������� ������ Fail
class function TResult<T>.Fail(const AError: string; const AErrorCode: integer; const ADetailMessage: string): TResult<T>;
begin
  Result.FSuccess := False;
  Result.FError := AError; // ������ ������
  Result.FErrorCode := AErrorCode;
  Result.FErrorDetail := ADetailMessage; // ������
  Result.FValue := Default(T);
end;

function TResult<T>.IsOk: boolean;
begin
  Result := FSuccess;
end;

function TResult<T>.IsFail: boolean;
begin
  Result := not FSuccess;
end;

function TResult<T>.OrDefault(const ADefault: T): T;
begin
  if FSuccess then
    Result := FValue
  else
    Result := ADefault;
end;

// --- ���������� TApiResult ---

class function TApiResult.Ok(const AValueJson: string): TApiResult;
begin
  Result.FSuccess := True;
  Result.FValue := AValueJson;
  Result.FStatusCode := 200; // �� ��������� ��� ������
  Result.FStatusValue := 'OK';
  Result.FError := '';
  Result.FErrorCode := 0;
  Result.FErrorType := '';
end;

// ��������: Fail ��������� StatusValue � DetailError
class function TApiResult.Fail(const AStatusValue: string; const AErrorCode: integer; const AErrorType: string; const ADetailError: string): TApiResult;
begin
  Result.FSuccess := False;
  Result.FValue := '';
  Result.FStatusCode := AErrorCode; // ���������� ��� ������ ��� ������ ��� �� ���������
  Result.FStatusValue := AStatusValue; // ������ ������
  Result.FError := ADetailError; // ��������� ���������
  Result.FErrorCode := AErrorCode;
  Result.FErrorType := AErrorType;
end;

function TApiResult.IsOk: boolean;
begin
  Result := FSuccess;
end;

function TApiResult.IsFail: boolean;
begin
  Result := not FSuccess;
end;

// ������� �������: ���������� ���� Value, ���� ��������� JSON-������
function TApiResult.GetJson: string;
var
  Json, Detail: ISuperObject;
begin
  if FSuccess then
  begin
    // ���� �����, ������ ���������� ����������� JSON
    Result := FValue;
  end
  else
  begin
    // ���� �������, �������� JSON �� �������
    Json := SO;
    Json.B['success'] := False;
    Json.S['type'] := FErrorType;
    Detail := SO;
    // ���������� FError (��������� ���������) ��� 'message'
    Detail.S['message'] := FError;
    Detail.I['code'] := FErrorCode;
    // ��������� ������ ������ ��� �������
    Detail.S['status'] := FStatusValue;
    Json.O['detail'] := Detail;
    // ���������� ���������� JSON-������
    Result := Json.AsJson(true, false); // true ��� ����������
  end;
end;

function FromClipboardExcel: TArray<TArray<string>>;
var
  Lines      : TArray<string>;
  Cells      : TArray<string>;
  RawLines   : TArray<string>;
  AClipboard : string;
  RowIndex   : integer;
  ColIndex   : integer;
  LineCount  : integer;
begin
  SetLength(Result, 0);
  AClipboard:=Clipboard.AsText;
  // ��������� ����� �� ������
  RawLines := AClipboard.Split([sLineBreak]);

  // ������� ������ ������ � �����
  LineCount := Length(RawLines);
  if LineCount=0 then exit;
  while (LineCount>0) and (RawLines[LineCount-1].Trim='') do dec(LineCount);

  SetLength(Lines, LineCount);
  Move(RawLines[0], Lines[0], LineCount * sizeOf(string));

  SetLength(Result, Length(Lines));
  for RowIndex := 0 to High(Lines) do
    begin
      Cells:=Lines[RowIndex].Split([#9]); // ���������
      SetLength(Result[RowIndex], Length(Cells));
      for ColIndex:=0 to High(Cells) do Result[RowIndex][ColIndex]:=Cells[ColIndex];
    end;
end;

function GetClipboardExcel: TArray<TArray<string>>;
var
  Data           : string;
  Lines          : TArray<string>;
  Handle         : HGlobal;
  Ptr            : PWideChar;
  i              : integer;
begin
  Result := nil;
  // Clipboard := TClipboard.Create; // �� ����� ���������, ���������� ���������� Clipboard
  try
    if Clipboard.HasFormat(CF_UNICODETEXT) then
    begin
      Clipboard.Open;
      try
        Handle := Clipboard.GetAsHandle(CF_UNICODETEXT);
        if Handle <> 0 then
        begin
          Ptr := GlobalLock(Handle);
          try
            Data := Ptr; // ������ ���������� PWideChar � string
            Lines := Data.Split([sLineBreak],TStringSplitOptions.ExcludeEmpty);
            SetLength(Result, Length(Lines));
            for i := 0 to High(Lines) do
              Result[i] := Lines[i].Split([#9]);
          finally
            GlobalUnlock(Handle);
          end;
        end;
      finally
        Clipboard.Close;
      end;
    end;
  finally
    // Clipboard.Free; // �� ����� �����������
  end;
end;


procedure SetRussianKeyboardLayout;
begin
  LoadKeyboardLayout('00000419', KLF_ACTIVATE); // 00000419 � ��� ������� ���������
end;

end.
