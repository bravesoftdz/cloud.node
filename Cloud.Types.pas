unit Cloud.Types;

interface

uses
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  Cloud.Utils;

type
  TCloudEvent = (EVENT_NONE,EVENT_ERROR,EVENT_CONNECTING,EVENT_CONNECTED,
    EVENT_DISCONNECTED,EVENT_REQUEST,EVENT_RESPONSE);

  TCloudTransaction = record
  public
    ID: string;
    Address: string;
    Operation: string;
    Date: TDateTime;
    Amount: Extended;
    Confirmations: Int64;
    class operator Implicit(const S: string): TCloudTransaction;
    class operator Implicit(const Transaction: TCloudTransaction): string;
  end;

  TCloudResponse = record
    Command: string;
    Args: string;
    class operator Implicit(const S: string): TCloudResponse;
  end;

  TCloudResponseError = record
    Code: string;
    function ErrorString: string;
    class operator Implicit(const S: string): TCloudResponseError;
    class operator Implicit(const Response: TCloudResponse): TCloudResponseError;
    class operator Implicit(const Error: TCloudResponseError): string;
  end;

  TCloudResponseLogin = record
    AccountID: string;
    AccessToken: string;
    class operator Implicit(const S: string): TCloudResponseLogin;
    class operator Implicit(const Response: TCloudResponse): TCloudResponseLogin;
  end;

  TCloudAddress = string;

  TCloudAddresses = array of TCloudAddress;

  TCloudAddressesHelper = record helper for TCloudAddresses
    function IsEmpty: Boolean;
  end;

  TCloudResponseGetAddresses = record
    Addresses: TCloudAddresses;
    Error: Boolean;
    ErrorText: string;
    class operator Implicit(const S: string): TCloudResponseGetAddresses;
    class operator Implicit(const Response: TCloudResponse): TCloudResponseGetAddresses;
  end;

  TCloudTransactions = array of TCloudTransaction;

  TCloudResponseTransactions = record
    Transactions: TCloudTransactions;
    class operator Implicit(const S: string): TCloudResponseTransactions;
    class operator Implicit(const Response: TCloudResponse): TCloudResponseTransactions;
  end;

  TCloudResponseCreateAddress = record
    Address: TCloudAddress;
    Error: Boolean;
    ErrorText: string;
    class operator Implicit(const S: string): TCloudResponseCreateAddress;
    class operator Implicit(const Response: TCloudResponse): TCloudResponseCreateAddress;
  end;

  TCloudResponseInit = record
    ConnectionID: string;
    class operator Implicit(const S: string): TCloudResponseInit;
    class operator Implicit(const Response: TCloudResponse): TCloudResponseInit;
  end;

  TCloudResponseRegistration = record
    AccountID: string;
    class operator Implicit(const S: string): TCloudResponseRegistration;
    class operator Implicit(const Response: TCloudResponse): TCloudResponseRegistration;
  end;

  TCloudResponseCurrentAddresses = record
    AddressBTC: TCloudAddress;
    AddressLTC: TCloudAddress;
    AddressETH: TCloudAddress;
    class operator Implicit(const S: string): TCloudResponseCurrentAddresses;
    class operator Implicit(const Addresses: TCloudResponseCurrentAddresses): string;
    class operator Implicit(const Response: TCloudResponse): TCloudResponseCurrentAddresses;
  end;

  TCloudResponseInfo = record
    Address: TCloudAddress;
    Amount: Extended;
    class operator Implicit(const S: string): TCloudResponseInfo;
    class operator Implicit(const Info: TCloudResponseInfo): string;
    class operator Implicit(const Response: TCloudResponse): TCloudResponseInfo;
  end;

  TCloudResponseSendTo = record
    Tx: string;
    class operator Implicit(const S: string): TCloudResponseSendTo;
    class operator Implicit(const SendTo: TCloudResponseSendTo): string;
    class operator Implicit(const Response: TCloudResponse): TCloudResponseSendTo;
  end;

  TCloudDelegate = class abstract
    procedure OnEvent(Event: TCloudEvent; const Text: string); virtual; abstract;
    procedure OnInit(const Init: TCloudResponseInit); virtual; abstract;
    procedure OnError(const Error: TCloudResponseError); virtual; abstract;
    procedure OnRegistration(const Registration: TCloudResponseRegistration); virtual; abstract;
    procedure OnLogin(const Login: TCloudResponseLogin); virtual; abstract;
    procedure OnAddresses(const Addresses: TCloudResponseGetAddresses); virtual; abstract;
    procedure OnCreateAddress(const Address: TCloudResponseCreateAddress); virtual; abstract;
    procedure OnTransactions(const Transactions: TCloudResponseTransactions); virtual; abstract;
    procedure OnAddress(const Address: TCloudResponseCurrentAddresses); virtual; abstract;
    procedure OnInfo(const Info: TCloudResponseInfo); virtual; abstract;
    procedure OnSendTo(const SendTo: TCloudResponseSendTo); virtual; abstract;
  end;

implementation

{ TCloudTransaction }

class operator TCloudTransaction.Implicit(const S: string): TCloudTransaction;
var Args: TArray<string>;
begin

  // 2MtTqBASvfDoyx7QZCRFcdj3EcRB8bDzKqz receive 1585731173 0.00010000 282
  // 3a78181b4dbb4c84e6e057c85c8ad832c3938f6102e7dc4eda217107d6867c05

  Args:=S.Split([' ']);

  Result.ID:=Args[5];
  Result.Address:=Args[0];
  Result.Operation:=Args[1];
  Result.Date:=UnixToDateTime(Args[2].ToInt64,False);
  Result.Amount:=StrToFloat(Args[3],FormatSettings.Invariant);
  Result.Confirmations:=StrToInt64(Args[4]);

end;

class operator TCloudTransaction.Implicit(const Transaction: TCloudTransaction): string;
begin

  Result:='tx:'+Transaction.ID+
    ' address:'+Transaction.Address+
    ' operation:'+Transaction.Operation+
    ' date:'+DateToISO8601(Transaction.Date)+
    ' amount:'+AmountToStr(Transaction.Amount)+
    ' confirmations:'+Transaction.Confirmations.ToString;

end;

{ TCloudResponse }

class operator TCloudResponse.Implicit(const S: string): TCloudResponse;
var I: Integer;
begin

  I:=S.IndexOfAny([' ']);
  if I=-1 then I:=Length(S);

  Result.Command:=S.Substring(0,I);
  Result.Args:=S.Substring(I+1);

end;

{ TCloudResponseError }

function TCloudResponseError.ErrorString: string;
begin

  if Code='20' then Exit('unknown wallet');
  if Code='23' then Exit('invalid email');
  if Code='93' then Exit('wrong password');
  if Code='211' then Exit('invalid refer');
  if Code='444' then Exit('account not have address');
  if Code='780' then Exit('address not found');
  if Code='781' then Exit('incorrect response from server');
  if Code='782' then Exit('insufficient funds');
  if Code='783' then Exit('no unspent transactions');
  if Code='816' then Exit('account not found');
  if Code='829' then Exit('duplicate email');

  Result:='';

end;

class operator TCloudResponseError.Implicit(const S: string): TCloudResponseError;
var Args: TArray<string>;
begin

  // U20 * 829

  Args:=S.Split([' '],'<','>');

  Result.Code:=Args[2];

end;

class operator TCloudResponseError.Implicit(const Response: TCloudResponse): TCloudResponseError;
begin
  Result:=Response.Args;
end;

class operator TCloudResponseError.Implicit(const Error: TCloudResponseError): string;
begin

  Result:=Error.ErrorString;

  if Result='' then
    Result:=Error.Code
  else
    Result:=Error.Code+':'+Result;

end;

{ TCloudResponseStartClient }

class operator TCloudResponseLogin.Implicit(const S: string): TCloudResponseLogin;
var Args: TArray<string>;
begin

  // U24 ipaltEriXoUVSDF7EC7xNmq7RhUnK1rH6h 1 23

  Args:=S.Split([' '],'<','>');

  Result.AccountID:=Args[3];
  Result.AccessToken:=Args[1];

end;

class operator TCloudResponseLogin.Implicit(const Response: TCloudResponse): TCloudResponseLogin;
begin
  Result:=Response.Args;
end;

{ TCloudAddressesHelper }

function TCloudAddressesHelper.IsEmpty: Boolean;
begin
  Result:=Length(Self)=0;
end;

{ TCloudResponseGetCloudAdreses }

class operator TCloudResponseGetAddresses.Implicit(const S: string): TCloudResponseGetAddresses;
var
  jsObject: TJSONObject;
  Args: TArray<string>;
begin

  // U25 ipaSPCvJPlJSCkWJSJhMe1mBwjgAfBt4kD
  // {"result":{"2MtTqBASvfDoyx7QZCRFcdj3EcRB8bDzKqz":{"purpose":"receive"},
  // "2MwmFMxzDavxgyYE69p5yw2xNyvRJ9f5Mtc":{"purpose":"receive"}},"error":null,"id":"BTCExposed"}

  Args:=S.Split([' '],'{','}');

  Result:=Default(TCloudResponseGetAddresses);

  jsObject:=TJSONObject.ParseJSONValue(Args[2]) as TJSONObject;

  if Assigned(jsObject) then
  begin

    Result.Error:=not jsObject.Values['error'].Null;

    if Result.Error then

      Result.ErrorText:=jsObject.GetValue<string>('error')

    else

      for var P in jsObject.GetValue<TJSONObject>('result') do
        Result.Addresses:=Result.Addresses+[P.JsonString.Value];

    jsObject.Free;

  end;

end;

class operator TCloudResponseGetAddresses.Implicit(const Response: TCloudResponse): TCloudResponseGetAddresses;
begin
  Result:=Response.Args;
end;

{ TCloudResponseListTransactions }

class operator TCloudResponseTransactions.Implicit(const S: string): TCloudResponseTransactions;
var Args: TArray<string>;
begin

  // U36 ipaebikmPfPya3jUixEHnSbCvAiKifRolN 3 <tx1> <tx2> <tx3>

  Args:=S.Split([' '],'<','>');

  Result:=Default(TCloudResponseTransactions);

  if Length(Args)>2 then
  for var I:=0 to StrToIntDef(Args[2],0)-1 do
  Result.Transactions:=Result.Transactions+[Args[3+I].Trim(['<','>'])];

end;

class operator TCloudResponseTransactions.Implicit(const Response: TCloudResponse): TCloudResponseTransactions;
begin
  Result:=Response.Args;
end;

{ TCloudResponseCreateNewAdres }

class operator TCloudResponseCreateAddress.Implicit(const S: string): TCloudResponseCreateAddress;
var
  jsObject: TJSONObject;
  Args: TArray<string>;
begin

  // U7 ipal2N680aCjPEam94DCjjL1RwtVb7VL6i {"result":"2MwmFMxzDavxgyYE69p5yw2xNyvRJ9f5Mtc",
  // "error":null,"id":"BTCExposed"}

  Args:=S.Split([' '],'{','}');

  Result:=Default(TCloudResponseCreateAddress);

  jsObject:=TJSONObject.ParseJSONValue(Args[2]) as TJSONObject;

  if Assigned(jsObject) then
  begin

    Result.Error:=not jsObject.Values['error'].Null;

    if Result.Error then

      Result.ErrorText:=jsObject.GetValue<string>('error')

    else

      Result.Address:=jsObject.GetValue<string>('result');

    jsObject.Free;

  end;

end;

class operator TCloudResponseCreateAddress.Implicit(const Response: TCloudResponse): TCloudResponseCreateAddress;
begin
  Result:=Response.Args;
end;

{ TCloudResponseInit }

class operator TCloudResponseInit.Implicit(const S: string): TCloudResponseInit;
var Args: TArray<string>;
begin

  // U101 *

  Args:=S.Split([' ']);

  Result.ConnectionID:=Args[0];

end;

class operator TCloudResponseInit.Implicit(const Response: TCloudResponse): TCloudResponseInit;
begin
  Result:=Response.Args;
end;

{ TCloudResponseRegLight }

class operator TCloudResponseRegistration.Implicit(const S: string): TCloudResponseRegistration;
var Args: TArray<string>;
begin

  // U7 23

  Args:=S.Split([' ']);

  Result.AccountID:=Args[1];

end;

class operator TCloudResponseRegistration.Implicit(const Response: TCloudResponse): TCloudResponseRegistration;
begin
  Result:=Response.Args;
end;

{ TCloudResponseGetAddress }

class operator TCloudResponseCurrentAddresses.Implicit(const S: string): TCloudResponseCurrentAddresses;
var
  Args: TArray<string>;
  L: Integer;
begin

  // U9 23 <2N7FbG7FkUpXtYJcRXe5wuM68wBv5bPEADT> <> <>

  Args:=S.Split([' '],'<','>');

  L:=Length(Args);

  Result:=Default(TCloudResponseCurrentAddresses);

  if L>2 then Result.AddressBTC:=Args[2].Trim(['<','>']);
  if L>3 then Result.AddressLTC:=Args[3].Trim(['<','>']);
  if L>4 then Result.AddressETH:=Args[4].Trim(['<','>']);

end;

class operator TCloudResponseCurrentAddresses.Implicit(const Addresses: TCloudResponseCurrentAddresses): string;
begin
  Result:=
    'BTC:'+Addresses.AddressBTC+' '+
    'LTC:'+Addresses.AddressLTC+' '+
    'ETH:'+Addresses.AddressETH;
end;

class operator TCloudResponseCurrentAddresses.Implicit(const Response: TCloudResponse): TCloudResponseCurrentAddresses;
begin
  Result:=Response.Args;
end;

{ TCloudResponseInfo }

class operator TCloudResponseInfo.Implicit(const S: string): TCloudResponseInfo;
var
  Args: TArray<string>;
  Value: string;
  P: Integer;
begin

  // U9 ipaVrAtleElE5ocnduDxylVeM20g58vfxm 2N7FbG7FkUpXtYJcRXe5wuM68wBv5bPEADT=0,00200000 18332

  Args:=S.Split([' ']);

  Result:=Default(TCloudResponseInfo);

  if Length(Args)>2 then
  begin

    Value:=Args[2];

    P:=Value.IndexOf('=');

    Result.Address:=Value.Substring(0,P);
    Result.Amount:=StrToAmount(Value.Substring(P+1));

  end;

end;

class operator TCloudResponseInfo.Implicit(const Info: TCloudResponseInfo): string;
begin
  Result:=Info.Address+'='+AmountToStr(Info.Amount);
end;

class operator TCloudResponseInfo.Implicit(const Response: TCloudResponse): TCloudResponseInfo;
begin
  Result:=Response.Args;
end;

{ TCloudResponseSendTo }

class operator TCloudResponseSendTo.Implicit(const S: string): TCloudResponseSendTo;
var Args: TArray<string>;
begin

  // U9 ipaVrAtleElE5ocnduDxylVeM20g58vfxm 308d8e07787bc9351250e1b714c39adb55177e53870ad6d944319e9ab52b28a0

  Args:=S.Split([' ']);

  Result.Tx:=Args[2];

end;

class operator TCloudResponseSendTo.Implicit(const SendTo: TCloudResponseSendTo): string;
begin
  Result:='tx:'+SendTo.Tx;
end;

class operator TCloudResponseSendTo.Implicit(const Response: TCloudResponse): TCloudResponseSendTo;
begin
  Result:=Response.Args;
end;

end.
