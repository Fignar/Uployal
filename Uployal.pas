{~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~}
{                                                                              }
{                             Class Uployal                                    }
{                                                                              }
{                   Copyright (c) 2024-2025 Бабенко Олег                       }
{                                19.12.2024                                    }
{                                                                              }
{    Refactored with TResult/TApiResult pattern by Gemini (27.10.2025)         }
{                                                                              }
{~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~}

unit Uployal;

interface

uses
  clEvents, SysUtils, Classes, xSuperObject,
  System.Net.HttpClient, System.Net.URLClient,
  AppUtils;

type
  TUployal         = class(TEvents)
  private
    FBaseUrl       : string;
    FBaseUrlShort  : string;
    FHawkID        : string;
    FHawkKey       : string;
    FTestMode      : boolean;
    function       CharInSet(C: AnsiChar; const CharSet: TSysCharSet): boolean; overload;
    function       CharInSet(C: WideChar; const CharSet: TSysCharSet): boolean; overload;
    function       URLEncode(const Url: Utf8String): string;
    function       CorrectionJSON(const s: string): string;
    procedure      LoadOpenSSLLibrary;
    function       GetPayloadHash(const Payload: string): string;
    function       GetHawkHeader(const AId, AKey, AMethod, AUri, AHost, APort, APayload: string): string;
    function       GetResult(const Response: IHTTPResponse): TResult<string>;
    function       ExecuteGet(const AResourceUri: string; const AFullUrl: string): TResult<string>;
    function       ExecutePost(const AResource: string; const APayload: string): TResult<string>;
    function       ConvertResult(const AResult: TResult<string>; const AErrorType: string): TApiResult;
  public
    constructor    Create(HawkID, HawkKey: string); overload;
    destructor     Destroy; override;

    function       GetClient(const Param: string): TApiResult;
    function       GetClients(const Params: TStringList): TApiResult;
    function       GetCategory: TApiResult;
    function       SetCategory(X: ISuperArray): TApiResult;
    function       GetProduct: TApiResult;
    function       SetProduct(X: ISuperArray): TApiResult;
    function       OrderOpen(X: ISuperObject): TApiResult;
    function       OrderClose(X: ISuperObject): TApiResult;
    function       OrderCancel(X: ISuperObject): TApiResult;
  end;

implementation

uses
  rxVCLUtils, DateUtils,
  System.JSON,
  Hash, NetEncoding,
  IdHMacSha1, IdCoderMIME, IdHashSHA, IdHMac, IdGlobal, IdSSLOpenSSL, IdCoder;

const
  NETWORK_ERROR_CODE = -1;

constructor TUployal.Create(HawkID, HawkKey: string);
begin
  inherited Create;
  FTestMode := true;
  if not FTestMode then
    FBaseUrl := ''
  else
  begin
    FBaseUrl := 'https://spa.disloy.com';
    FBaseUrlShort := 'spa.disloy.com';
  end;
  FHawkID := HawkID;
  FHawkKey := HawkKey;
end;

destructor TUployal.Destroy;
begin
  inherited;
end;

function TUployal.CharInSet(C: AnsiChar; const CharSet: TSysCharSet): Boolean;
begin
  Result := C in CharSet;
end;

function TUployal.CharInSet(C: WideChar; const CharSet: TSysCharSet): Boolean;
begin
  Result := (C < #$0100) and (AnsiChar(C) in CharSet);
end;

function TUployal.URLEncode(const Url: Utf8String): string;
var
 i: Integer;
begin
  Result := '';
  for i := 1 to length(Url) do
  begin
    if CharInSet(Url[I],['A'..'Z','a'..'z','0'..'9','-','=','&', ':', '/', '?', ';', '_'])
      then Result := Result + Utf8ToAnsi(Url[I])
      else Result := Result + '%' + IntToHex(Ord(Url[I]), 2);
  end;
end;

function TUployal.CorrectionJSON(const s: string): string;
var
  X: ISuperObject;
  Y: TJSONValue;
begin
  // Проверяем на пустую строку
  if Trim(s) = '' then Exit('');

  try
    Y := TJSONObject.ParseJSONValue(s);
    if Assigned(Y) then
      X := SO(s)
    else
    begin
      X := SO;
      X.S['error'] := s; // Если парсинг не удался, возвращаем объект с полем error
    end;
    Result := X.AsJSon;
  finally
    if Assigned(Y) then Y.Free;
  end;
end;

procedure TUployal.LoadOpenSSLLibrary;
begin
  if not IdSSLOpenSSL.LoadOpenSSLLibrary
    then raise Exception.Create('Не удалось загрузить библиотеки OpenSSL');
end;

function TUployal.GetPayloadHash(const Payload: string): string;
var
  HashData: TBytes;
begin
  HashData := THashSHA2.GetHashBytes('hawk.1.payload' + #10 + 'application/json' + #10 + Payload + #10, THashSHA2.TSHA2Version.SHA256);
  Result := TNetEncoding.Base64.EncodeBytesToString(HashData);
end;

function TUployal.GetHawkHeader(const AId, AKey, AMethod, AUri, AHost, APort, APayload: string): string;
var
  LTimestamp: string;
  LNonce: string;
  LNormalizedString: string;
  LMac: string;
  LHMAC: TIdHMACSHA256;
  LPayload: string;
  IsPayload: boolean;
begin
  try
    LoadOpenSSLLibrary; // Убедимся, что SSL загружен
  except
     on E: Exception do raise Exception.Create('Ошибка при загрузке OpenSSL для Hawk: ' + E.Message);
  end;

  IsPayload := length(APayload) > 0;
  LTimestamp := IntToStr(DateTimeToUnix(Now, false));
  LNonce := IntToHex(Random(MaxInt), 6);

  if IsPayload
    then LPayload := GetPayloadHash(APayload)
    else LPayload := '';

  LNormalizedString := 'hawk.1.header' + #10 +
    LTimestamp + #10 +
    LNonce + #10 +
    UpperCase(AMethod) + #10 +
    AUri + #10 +
    LowerCase(AHost) + #10 +
    APort + #10 +
    LPayload + #10 +
    '' + #10;

  LHMAC := TIdHMACSHA256.Create;
  try
    LHMAC.Key := ToBytes(AKey, IndyTextEncoding_UTF8);
    // TIdEncoderMIME.EncodeBytes устарел, используем TNetEncoding
    LMac := TNetEncoding.Base64.EncodeBytesToString(LHMAC.HashValue(ToBytes(LNormalizedString, IndyTextEncoding_UTF8)));
  finally
    LHMAC.Free;
  end;

  if IsPayload
    then Result:=Format('Hawk id="%s",ts="%s",nonce="%s",hash="%s",mac="%s"',[AId,LTimestamp,LNonce,LPayload,LMac])
    else Result:=Format('Hawk id="%s",ts="%s",nonce="%s",mac="%s"',[AId,LTimestamp,LNonce,LMac]);
end;

// --- Внутренние методы ---

// ИЗМЕНЕНО: Использует новую TResult<T>.Fail с DetailMessage
function TUployal.GetResult(const Response: IHTTPResponse): TResult<string>;
var
  Content: string;
  LDetailError: string;
begin
  Content := CorrectionJSON(Response.ContentAsString);

  if (Response.StatusCode >= 200) and (Response.StatusCode < 300) then
  begin
    Result := TResult<string>.Ok(Content);
  end
  else
  begin
    // Формируем детальное сообщение
    LDetailError := Format('%s. Details: %s', [Response.StatusText, Content]);
    // Передаем чистый статус и детали раздельно
    Result := TResult<string>.Fail(
      Response.StatusText, // Чистый статус (для StatusValue)
      Response.StatusCode,
      LDetailError        // Детальное сообщение (для Error/Message)
    );
  end;
end;

// ExecuteGet
function TUployal.ExecuteGet(const AResourceUri: string; const AFullUrl: string): TResult<string>;
var
  HTTPClient: THTTPClient;
  Response: IHTTPResponse;
  HawkHeader: string;
begin
  HTTPClient := THTTPClient.Create;
  try
    HawkHeader := GetHawkHeader(FHawkID, FHawkKey, 'GET', AResourceUri, FBaseUrlShort, '443', '');
    HTTPClient.CustomHeaders['Authorization'] := HawkHeader;
    try
      Response := HTTPClient.Get(AFullUrl);
    except
      on E: ENetHttpClientException do // Ловим специфичное исключение
        Exit(TResult<string>.Fail('Network Error: ' + E.Message, NETWORK_ERROR_CODE, E.Message));
      on E: Exception do // Ловим другие возможные ошибки
        Exit(TResult<string>.Fail('Error during GET request: ' + E.Message, -2, E.Message)); // Общий код ошибки
    end;
    Result := GetResult(Response);
  finally
    HTTPClient.Free;
  end;
end;

// ExecutePost
function TUployal.ExecutePost(const AResource: string; const APayload: string): TResult<string>;
var
  HTTPClient: THTTPClient;
  RequestContent: TStringStream;
  Response: IHTTPResponse;
  HawkHeader: string;
begin
  HTTPClient := THTTPClient.Create;
  RequestContent := TStringStream.Create(APayload, TEncoding.UTF8);
  try
    HawkHeader := GetHawkHeader(FHawkID, FHawkKey, 'POST', AResource, FBaseUrlShort, '443', APayload);
    HTTPClient.ContentType := 'application/json';
    HTTPClient.CustomHeaders['Authorization'] := HawkHeader;
    try
      Response := HTTPClient.Post(FBaseUrl + AResource, RequestContent);
    except
      on E: ENetHttpClientException do
        Exit(TResult<string>.Fail('Network Error: ' + E.Message, NETWORK_ERROR_CODE, E.Message));
      on E: Exception do
        Exit(TResult<string>.Fail('Error during POST request: ' + E.Message, -2, E.Message));
    end;
    Result := GetResult(Response);
  finally
    HTTPClient.Free;
    RequestContent.Free;
  end;
end;

// ИЗМЕНЕНО: Использует DetailMessage из TResult<T> для ADetailError в TApiResult.Fail
function TUployal.ConvertResult(const AResult: TResult<string>; const AErrorType: string): TApiResult;
begin
  if AResult.IsOk then
    Result := TApiResult.Ok(AResult.Value)
  else
    Result := TApiResult.Fail(
      AResult.Error,         // Чистый статус -> StatusValue
      AResult.ErrorCode,
      AErrorType,
      AResult.ErrorDetail // Детали -> Error
    );
end;

// --- Публичные методы (без изменений, т.к. используют ConvertResult) ---
function TUployal.GetClient(const Param: string): TApiResult;
const Resource = '/api/rs/v2/consumer/';
var
  URI: TURI;
  FullURL, ResourceUri: string;
begin
  URI := TURI.Create(FBaseUrl + Resource);
  case Length(trim(Param)) of
    10: URI.AddParameter('mobile_phone', Param);
    13: URI.AddParameter('consumer_uid', Param);
  end;
  FullURL := URI.ToString;
  ResourceUri := FullURL.Replace(FBaseUrl, '');
  Result := ConvertResult(ExecuteGet(ResourceUri, FullURL), 'CLIENT_GET_ERROR');
end;

function TUployal.GetClients(const Params: TStringList): TApiResult;
const Resource = '/api/rs/v2/consumer/fetch/';
var
  URI: TURI;
  FullURL, ResourceUri: string;
begin
  URI := TURI.Create(FBaseUrl + Resource);
  for var i := 0 to Params.Count - 1 do
    URI.AddParameter(Params.Names[i], Params.ValueFromIndex[i]);
  FullURL := URI.ToString;
  ResourceUri := FullURL.Replace(FBaseUrl, '');
  Result := ConvertResult(ExecuteGet(ResourceUri, FullURL), 'CLIENT_FETCH_ERROR');
end;

function TUployal.GetCategory: TApiResult;
const Resource = '/api/rs/v2/category/';
begin
  Result := ConvertResult(ExecuteGet(Resource, FBaseUrl + Resource), 'CATEGORY_GET_ERROR');
end;

function TUployal.SetCategory(X: ISuperArray): TApiResult;
const Resource = '/api/rs/v2/category/';
begin
  Result := ConvertResult(ExecutePost(Resource, X.AsJSon), 'CATEGORY_SET_ERROR');
end;

function TUployal.GetProduct: TApiResult;
const Resource = '/api/rs/v2/product/';
var
  URI: TURI;
  FullURL, ResourceUri: string;
begin
  URI := TURI.Create(FBaseUrl + Resource);
  // Добавляем параметры по умолчанию, если нужно
  URI.AddParameter('page_size', '100'); // Пример
  URI.AddParameter('page', '1');      // Пример
  FullURL := URI.ToString;
  ResourceUri := FullURL.Replace(FBaseUrl, '');
  Result := ConvertResult(ExecuteGet(ResourceUri, FullURL), 'PRODUCT_GET_ERROR');
end;

function TUployal.SetProduct(X: ISuperArray): TApiResult;
const Resource = '/api/rs/v2/product/';
begin
  Result := ConvertResult(ExecutePost(Resource, X.AsJSon), 'PRODUCT_SET_ERROR');
end;

function TUployal.OrderOpen(X: ISuperObject): TApiResult;
const Resource = '/api/rs/v2/order/open/';
begin
  Result := ConvertResult(ExecutePost(Resource, X.AsJSon), 'ORDER_OPEN_ERROR');
end;

function TUployal.OrderClose(X: ISuperObject): TApiResult;
const Resource = '/api/rs/v2/order/close/';
begin
  Result := ConvertResult(ExecutePost(Resource, X.AsJSon), 'ORDER_CLOSE_ERROR');
end;

function TUployal.OrderCancel(X: ISuperObject): TApiResult;
const Resource = '/api/rs/v2/order/cancel/';
begin
  Result := ConvertResult(ExecutePost(Resource, X.AsJSon), 'ORDER_CANCEL_ERROR');
end;

end.
