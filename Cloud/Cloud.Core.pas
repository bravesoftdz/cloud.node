unit Cloud.Core;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  App.Intf,
  DEX.Types,
  Cloud.Types,
  Cloud.Consts,
  Cloud.Client,
  Cloud.Log,
  Cloud.Utils;

type

  TInfoProc = reference to procedure(const Info: TCloudResponseInfo);
  TErrorProc = reference to procedure(const Error: TCloudResponseError);
  TOfferAccountProc = reference to procedure(AccountID: Integer);

  TCloudCore = class(TCloudDelegate)
  private
    CloudHost: string;
    CloudPort: Word;
    KeepAlive: Boolean;
    procedure ReadConfig(jsConfig: TJSONObject);
  private
    Queue: array of TProc;
    procedure Enqueue(const Name: string; Proc: TProc);
    procedure Dequeue;
  private
    Client: TCloudClient;
    OfferAccount: Int64;
    FShowEventMessages: Boolean;
    procedure DoExcept(const Text: string);
    procedure DoConnection;
    procedure ExecuteBeginProc;
  private
    DoRegistrationProc: TProc;
    DoLoginProc: TProc;
    DoConnectProc: TProc;
    DoBeginProc: TProc;
    DoErrorProcDefault: TErrorProc;
    DoErrorProc: TErrorProc;
    DoInfoProc: TInfoProc;
    DoCreateAddressProc: TProc;
    DoSendToProc: TProc;
    DoOfferAccountProc: TOfferAccountProc;
    DoCreateOfferProc: TProc;
  private
    procedure OnEvent(Event: TCloudEvent; const Text: string); override;
    procedure OnInit(const Init: TCloudResponseInit); override;
    procedure OnError(const Error: TCloudResponseError); override;
    procedure OnRegistration(const Registration: TCloudResponseRegistration); override;
    procedure OnLogin(const Login: TCloudResponseLogin); override;
    procedure OnAddresses(const Addresses: TCloudResponseGetAddresses); override;
    procedure OnCreateAddress(const Address: TCloudResponseCreateAddress); override;
    procedure OnTransactions(const Transactions: TCloudResponseTransactions); override;
    procedure OnAddress(const Address: TCloudResponseCurrentAddresses); override;
    procedure OnInfo(const Info: TCloudResponseInfo); override;
    procedure OnSendTo(const SendTo: TCloudResponseSendTo); override;
    procedure OnRatio(const Ratio: TCloudResponseRatio); override;
    procedure OnRequestForging(const Forging: TCloudRequestForging); override;
    procedure OnForging(const Forging: TCloudResponseForging); override;
    procedure OnRequestAccountBalance(const AccountBalance: TCloudRequestAccountBalance); override;
    procedure OnCreateOffer(const Offer: TCloudResponseCreateOffer); override;
    procedure OnOffers(const Offers: TCloudResponseOffers); override;
    procedure OnOfferAccount(const Account: TCloudResponseOfferAccount); override;
    procedure OnRequestTransfer(const Transfer: TCloudRequestTransfer); override;
    procedure OnKillOffers(const Offers: TCloudResponseKillOffers); override;
    procedure OnActiveOffers(const Offers: TCloudResponseOffers); override;
    procedure OnClosedOffers(const Offers: TCloudResponseOffers); override;
    procedure OnHistoryOffers(const Offers: TCloudResponseOffers); override;
    procedure OnPairsSummary(const Pairs: TCloudResponsePairs); override;
    procedure OnSetNotifications(const Notifications: TCloudResponseNotifications); override;
    procedure OnNotifyEvent(const NotifyEvent: TCloudResponseNotifyEvent); override;
    procedure OnCandles(const Candles: TCloudResponseCandles); override;
    procedure OnTradingHistory(const Trades: TCloudResponseTrades); override;
  public
    constructor Create; overload;
    destructor Destroy; override;
    function Workloaded: Boolean;
    procedure Connect;
    procedure Disconnect;
    procedure Unauthorized;
    procedure Cancel;
    function Ready: Boolean;
    procedure SetNetwork(const NetworkName: string; jsConfig: TJSONObject);
    procedure SetAuth(const Email,Password: string; AccountID: Int64);
    procedure SetKeepAlive(KeepAlive: Boolean; RecoveryInterval: Cardinal);
    procedure SendRequestLogin;
    procedure SendRequestBalance(const Symbol: string);
    procedure SendRequestTransfer(const Symbol,Address: string; Amount: Extended);
    procedure SendRequestRatio;
    procedure SendRequestForging(Owner,TokenID: Int64; const Symbol: string;
      BuyAmount,PayAmount,Ratio,Commission1,Commission2: Extended);
    procedure SendRequestCreateOffer(Direction: Integer; const Symbol1,Symbol2: string;
      Amount,Ratio: Extended; EndDate: TDateTime);
    procedure SendRequestOffers(const Symbol1,Symbol2: string);
    procedure SendRequestKillOffers(const Offers: TArray<Int64>);
    procedure SendRequestActiveOffer;
    procedure SendRequestClosedOffer(BeginDate,EndDate: TDateTime);
    procedure SendRequestHistoryOffer(BeginDate,EndDate: TDateTime);
    procedure SendRequestPairsSummary;
    procedure SendRequestCandles(const Symbol1,Symbol2: string; BeginDate: TDateTime;
      IntervalType: Integer);
    procedure SendRequestSetNotifications(Enabled: Boolean);
    procedure SendRequestTradingHistory(const Symbol1,Symbol2: string; Count: Integer);
    property ShowEventMessages: Boolean read FShowEventMessages write FShowEventMessages;
  end;

implementation

constructor TCloudCore.Create;
begin

  Client:=TCloudClient.Create;
  Client.SetDelegate(Self);

  DoErrorProcDefault:=procedure(const Error: TCloudResponseError)
  begin
    if Error.Code='816' then
      DoRegistrationProc
    else
      DoExcept(Error.ErrorString);
  end;

  SetAuth('','',0);

end;

destructor TCloudCore.Destroy;
begin
  Client.Free;
  inherited;
end;

procedure TCloudCore.ReadConfig(jsConfig: TJSONObject);
var jsCloud: TJSONObject;
begin

  if Assigned(jsConfig) then
  begin

    jsCloud:=jsConfig.GetValue<TJSONObject>('cloud',nil);

    if Assigned(jsCloud) then
    begin
      CloudHost:=jsCloud.GetValue<string>('host');
      CloudPort:=jsCloud.GetValue<Word>('port');
      KeepAlive:=jsCloud.GetValue<Boolean>('keepalive',False);
    end;

  end;

end;

function TCloudCore.Workloaded: Boolean;
begin
  Result:=Client.Workloaded;
end;

procedure TCloudCore.Enqueue(const Name: string; Proc: TProc);
begin

  if Length(Queue)>10 then
  begin

    Cancel;

    UI.ShowException('too many requests');

  end else begin

    Queue:=Queue+[Proc];

    ToLog('Add procedure '+Name+' to queue['+High(Queue).ToString+']');

    if Length(Queue)=1 then Queue[0]();

  end;

end;

procedure TCloudCore.Dequeue;
begin
  Delete(Queue,0,1);
  if Length(Queue)>0 then Queue[0]() else
  DoBeginProc:=nil;
end;

procedure TCloudCore.DoExcept(const Text: string);
begin

  ToLog('error:'+Text);

  UI.WaitCancel;

  UI.ShowException(Text);

  UI.WaitUnlock;

  Dequeue;

end;

procedure TCloudCore.DoConnection;
begin

  if not Client.Connected then
    Client.Connect
  else if not Client.Authorized then
    DoLoginProc
  else
    ExecuteBeginProc;

end;

procedure TCloudCore.OnEvent(Event: TCloudEvent; const Text: string);
begin

  ToLog(Text);

  if ShowEventMessages then

  case Event of
  EVENT_REQUEST: UI.ShowMessage('>'+Text);
  EVENT_RESPONSE: UI.ShowMessage('<'+Text);
  else UI.ShowMessage(Text);
  end;

end;

procedure TCloudCore.OnError(const Error: TCloudResponseError);
begin
  ToLog(Error);
  DoErrorProc(Error);
end;

procedure TCloudCore.OnInit(const Init: TCloudResponseInit);
begin
  DoConnectProc;
end;

procedure TCloudCore.OnRegistration(const Registration: TCloudResponseRegistration);
begin
  DoLoginProc;
end;

procedure TCloudCore.OnLogin(const Login: TCloudResponseLogin);
begin
  AppCore.DoCloudLogin;
  ExecuteBeginProc;
end;

procedure TCloudCore.OnInfo(const Info: TCloudResponseInfo);
begin
  DoInfoProc(Info);
end;

procedure TCloudCore.OnAddresses(const Addresses: TCloudResponseGetAddresses);
begin

end;

procedure TCloudCore.OnCreateAddress(const Address: TCloudResponseCreateAddress);
begin
  DoCreateAddressProc;
end;

procedure TCloudCore.OnTransactions(const Transactions: TCloudResponseTransactions);
begin

end;

procedure TCloudCore.OnAddress(const Address: TCloudResponseCurrentAddresses);
begin

end;

procedure TCloudCore.OnSendTo(const SendTo: TCloudResponseSendTo);
begin
  DoSendToProc;
end;

procedure TCloudCore.OnRatio(const Ratio: TCloudResponseRatio);
begin

  UI.WaitCancel;

  AppCore.DoCloudRatio(Ratio.RatioBTC,Ratio.RatioLTC,Ratio.RatioETH);

  UI.WaitUnlock;

  Dequeue;

end;

// on owner RLC and GTN tokens node

procedure TCloudCore.OnRequestForging(const Forging: TCloudRequestForging);
var R: string;
begin

  R:='0'; // failed

  try

    AppCore.DoForging(Forging.Owner,Forging.Buyer,Forging.BuyToken,Forging.BuyAmount,
      Forging.Commission1,Forging.Commission2);

    R:='1'; // success

  except on E: Exception do
    ToLog('Exception: '+E.Message);
  end;

  Client.SendResponseForging(Forging.Request,R); // response to cloud

end;

procedure TCloudCore.OnForging(const Forging: TCloudResponseForging);
begin

  if Forging.Result=1 then
  begin

    UI.WaitCancel;

    AppCore.DoCloudForgingResult(Forging.Tx);

    UI.WaitUnlock;

    Dequeue;

  end else
    DoExcept('error');

end;

// on cloud node

procedure TCloudCore.OnRequestAccountBalance(const AccountBalance: TCloudRequestAccountBalance);
var AmountRLC,AmountGTN: Extended;
begin

  AmountRLC:=AppCore.GetSymbolBalance('RLC');
  AmountGTN:=AppCore.GetSymbolBalance('GTN');

  Client.SendResponseAccountBalance(AmountRLC,AmountGTN); // response to cloud

end;

procedure TCloudCore.OnCreateOffer(const Offer: TCloudResponseCreateOffer);
begin

  UI.WaitCancel;

  AppCore.DoCloudCreateOffer(Offer.OfferID);

  UI.WaitUnlock;

  Dequeue;

end;

function CloudOfferToOffer(const Offer: TCloudOffer): TOffer;
begin
  Result.Status:=Offer.Status;
  Result.ID:=Offer.ID;
  Result.AccountID:=Offer.AccountID;
  Result.Direction:=Offer.Direction;
  Result.Symbol1:=SymbolBy(Offer.SymbolID1);
  Result.Symbol2:=SymbolBy(Offer.SymbolID2);
  Result.Ratio:=Offer.Ratio;
  Result.StrtAmount:=Offer.StrtAmount;
  Result.CrrntAmount:=Offer.CrrntAmount;
  Result.StartDate:=Offer.StartDate;
  Result.LastDate:=Offer.LastDate;
  Result.EndDate:=Offer.EndDate;
end;

function CloudOffersToOffers(const Offers: TCloudOffers): TOffers;
begin
  Result:=nil;
  for var Offer in Offers do Result:=Result+[CloudOfferToOffer(Offer)];
end;

function CloudPairToPair(const Pair: TCloudPair): TPair;
begin

  Result.Symbol1:=SymbolBy(Pair.SymbolID1);
  Result.Symbol2:=SymbolBy(Pair.SymbolID2);
  Result.Ratio:=Pair.Ratio;
  Result.Volume:=Pair.Volume;
  Result.LastDate:=Pair.LastDate;
  Result.Ratio24hAgo:=Pair.Ratio24hAgo;
  Result.Low:=Pair.Low;
  Result.High:=Pair.High;

  if Result.Ratio24hAgo>0 then
    Result.Percent:=100*(Result.Ratio/Result.Ratio24hAgo-1)
  else
    Result.Percent:=0;

end;

function CloudPairsToPairs(const Pairs: TCloudPairs): TPairs;
begin
  Result:=nil;
  for var Pair in Pairs do Result:=Result+[CloudPairToPair(Pair)];
end;

procedure TCloudCore.OnOffers(const Offers: TCloudResponseOffers);
begin

  UI.WaitCancel;

  AppCore.DoCloudOffers(CloudOffersToOffers(Offers.Offers));

  UI.WaitUnlock;

  Dequeue;

end;

procedure TCloudCore.OnOfferAccount(const Account: TCloudResponseOfferAccount);
begin
  DoOfferAccountProc(Account.AccountID);
end;

function AnyOf(const S: string; const Values: array of string): Boolean;
begin
  Result:=False;
  for var V in Values do if SameText(S,V) then Exit(True);
end;

// on cloud node

procedure TCloudCore.OnRequestTransfer(const Transfer: TCloudRequestTransfer);
var Symbol: string;
begin

  Symbol:=SymbolBy(Transfer.SymbolID);

  if not AnyOf(Symbol,['RLC','GTN']) then
    Client.SendResponseError(1109,'wrong coin')
  else

  if not (Transfer.Amount>0) then
    Client.SendResponseError(1111,'wrong amount')
  else

  if Transfer.Amount>AppCore.GetSymbolBalance(Symbol) then
    Client.SendResponseError(782,'insufficient funds')

  else try

    // blockchain transfer

    AppCore.DoTransferToken2(SymbolBy(Transfer.SymbolID),Transfer.ToAccountID.ToString,Transfer.Amount);

    Client.SendResponseTransfer; // success response to cloud

  except on E: Exception do
    Client.SendResponseError(781,E.Message); // any transfer exception
  end;

end;

procedure TCloudCore.OnKillOffers(const Offers: TCloudResponseKillOffers);
begin

  UI.WaitCancel;

  AppCore.DoCloudKillOffers(Offers.Offers);

  UI.WaitUnlock;

  Dequeue;

end;

procedure TCloudCore.OnActiveOffers(const Offers: TCloudResponseOffers);
begin

  UI.WaitCancel;

  AppCore.DoCloudActiveOffers(CloudOffersToOffers(Offers.Offers));

  UI.WaitUnlock;

  Dequeue;

end;

procedure TCloudCore.OnClosedOffers(const Offers: TCloudResponseOffers);
begin

  UI.WaitCancel;

  AppCore.DoCloudClosedOffers(CloudOffersToOffers(Offers.Offers));

  UI.WaitUnlock;

  Dequeue;

end;

procedure TCloudCore.OnHistoryOffers(const Offers: TCloudResponseOffers);
begin

  UI.WaitCancel;

  AppCore.DoCloudHistoryOffers(CloudOffersToOffers(Offers.Offers));

  UI.WaitUnlock;

  Dequeue;

end;

procedure TCloudCore.OnPairsSummary(const Pairs: TCloudResponsePairs);
begin

  UI.WaitCancel;

  AppCore.DoCloudPairsSummary(CloudPairsToPairs(Pairs.Pairs));

  UI.WaitUnlock;

  Dequeue;

end;

procedure TCloudCore.OnSetNotifications(const Notifications: TCloudResponseNotifications);
begin

  AppCore.DoCloudSetNotifications(Notifications.Enabled);

  Dequeue;

end;

procedure TCloudCore.OnNotifyEvent(const NotifyEvent: TCloudResponseNotifyEvent);
begin

  AppCore.DoCloudNotifyEvent(SymbolBy(NotifyEvent.SymbolID1),SymbolBy(NotifyEvent.SymbolID2),
    NotifyEvent.EventCode);

  Dequeue;

end;

function CloudCandleToCandle(const Candle: TCloudCandle): TDataCandle;
begin
  Result.DateTime:=Candle.DateTime;
  Result.Time:=Candle.UnixTime;
  Result.Open:=Candle.Open;
  Result.Close:=Candle.Close;
  Result.Min:=Candle.Min;
  Result.Max:=Candle.Max;
  Result.Volume:=Candle.Volume;
end;

function CloudCandlesToCandles(const Candles: TCloudCandles): TDataCandles;
begin
  Result:=nil;
  for var Candle in Candles do Result:=Result+[CloudCandleToCandle(Candle)];
end;

procedure TCloudCore.OnCandles(const Candles: TCloudResponseCandles);
begin

  UI.WaitCancel;

  AppCore.DoCloudCandles(SymbolBy(Candles.SymbolID1),SymbolBy(Candles.SymbolID2),
    Candles.IntervalCode,CloudCandlesToCandles(Candles.Candles));

  UI.WaitUnlock;

  Dequeue;

end;

function CloudTradeToTrade(const Trade: TCloudTrade): TDataTrade;
begin
  Result.Direction:=Trade.Direction;
  Result.Volume:=Trade.Volume;
  Result.Ratio:=Trade.Ratio;
  Result.Date:=Trade.Date;
end;

function CloudTradesToTrades(const Trades: TCloudTrades): TDataTrades;
begin
  Result:=nil;
  for var Trade in Trades do Result:=Result+[CloudTradeToTrade(Trade)];
end;

procedure TCloudCore.OnTradingHistory(const Trades: TCloudResponseTrades);
begin

  AppCore.DoCloudTradingHistory(SymbolBy(Trades.SymbolID1),SymbolBy(Trades.SymbolID2),
    CloudTradesToTrades(Trades.Trades));

  Dequeue;

end;

procedure TCloudCore.Connect;
begin

  Cancel;

  DoConnectProc:=procedure begin end;

  Client.Connect;

end;

procedure TCloudCore.Disconnect;
begin
  UI.ShowMessage('Disconnected');
  Client.Disconnect;
end;

procedure TCloudCore.Unauthorized;
begin
  UI.ShowMessage('Unauthorized');
  Client.Unauthorized;
end;

procedure TCloudCore.Cancel;
begin
  Queue:=nil;
  DoBeginProc:=nil;
  Client.Cancel;
end;

function TCloudCore.Ready: Boolean;
begin
  Result:=Client.Ready;
end;

procedure TCloudCore.ExecuteBeginProc;
begin
  if Assigned(DoBeginProc) then DoBeginProc;
end;

procedure TCloudCore.SetNetwork(const NetworkName: string; jsConfig: TJSONObject);
begin

  {$IFDEF STAGE}

  if NetworkName='mainnet' then
    CloudHost:=CLOUD_HOST_MAINNET
  else
    CloudHost:=CLOUD_HOST_TESTNET;

  {$ELSE}

  CloudHost:=CLOUD_HOST_DEVNET;

  {$ENDIF}

  CloudPort:=CLOUD_PORT_DEFAULT;

  KeepAlive:=False;

  OfferAccount:=0;

  ReadConfig(jsConfig);

  Client.SetEndPoint(CloudHost,CloudPort);

  SetAuth('','',0);

end;

procedure TCloudCore.SetAuth(const Email,Password: string; AccountID: Int64);
begin

  Client.Unauthorized;

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoRegistrationProc:=procedure
  begin
    Client.SendRequestRegistration(Email,Password,AccountID);
  end;

  DoLoginProc:=procedure
  begin
    Client.SendRequestLogin(Email,Password);
  end;

end;

procedure TCloudCore.SetKeepAlive(KeepAlive: Boolean; RecoveryInterval: Cardinal);
begin

  Client.KeepAlive:=KeepAlive or Self.KeepAlive;
  Client.SetRecoveryInterval(RecoveryInterval);

  if Client.KeepAlive then SendRequestLogin;

end;

procedure TCloudCore.SendRequestLogin;
begin

  Enqueue('SendRequestLogin',procedure
  begin

  ToLog('Execute login');

  Client.Unauthorized;

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoBeginProc:=procedure
  begin
    UI.WaitCancel;
    UI.WaitUnlock;
    Dequeue;
  end;

  UI.WaitLock;

  DoConnection;

  end);

end;

procedure TCloudCore.SendRequestBalance(const Symbol: string);
begin

  Enqueue('SendRequestBalance',procedure
  var Port: string;
  begin

  ToLog('Execute request balance '+Symbol);

  UI.WaitLock;

  Port:=SymbolToPort(Symbol);

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=procedure(const Error: TCloudResponseError)
  begin
    if Error.Code='780' then
      Client.SendRequestCreateAddress(Port)
    else
      DoErrorProcDefault(Error);
  end;

  DoBeginProc:=procedure
  begin
    Client.SendRequestInfo(Port);
  end;

  DoCreateAddressProc:=DoBeginProc;

  DoInfoProc:=procedure(const Info: TCloudResponseInfo)
  begin

    UI.WaitCancel;

    AppCore.DoCloudBalance(Info.Address,Info.Amount,PortToSymbol(Info.Port,Symbol));

    UI.WaitUnlock;

    Dequeue;

  end;

  if Port='' then
    DoExcept('forbidden coin')
  else
    DoConnection;

  end);

end;

procedure TCloudCore.SendRequestTransfer(const Symbol,Address: string; Amount: Extended);
begin

  Enqueue('SendRequestTransfer',procedure
  var Port: string;
  begin

  ToLog('Execute request transfer '+AmountToStr(Amount)+' '+Symbol+' to '+ Address);

  UI.WaitLock;

  Port:=SymbolToPort(Symbol);

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoBeginProc:=procedure
  begin
    Client.SendRequestSendTo(Address,Amount,6,Port);
  end;

  DoInfoProc:=procedure(const Info: TCloudResponseInfo)
  begin

    UI.WaitCancel;

    AppCore.DoCloudBalance(Info.Address,Info.Amount,PortToSymbol(Info.Port,Symbol));

    UI.WaitUnlock;

    Dequeue;

  end;

  DoSendToProc:=procedure
  begin
    Client.SendRequestInfo(Port);
  end;

  if Port='' then
    DoExcept('forbidden coin')
  else
    DoConnection;

  end);

end;

procedure TCloudCore.SendRequestRatio;
begin

  Enqueue('SendRequestRatio',procedure
  begin

  ToLog('Execute request ratio');

  UI.WaitLock;

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoBeginProc:=procedure
  begin
    Client.SendRequestRatio;
  end;

  DoConnection;

  end);

end;

procedure TCloudCore.SendRequestForging(Owner,TokenID: Int64; const Symbol: string;
  BuyAmount,PayAmount,Ratio,Commission1,Commission2: Extended);
begin

  Enqueue('SendRequestForging',procedure
  var Port: string;
  begin

  ToLog('Execute request forging TokenID='+TokenID.ToString+' '+AmountToStr(BuyAmount)+' '+
    AmountToStr(PayAmount)+' '+Symbol+' to AccountID='+Owner.ToString);

  UI.WaitLock;

  Port:=SymbolToPort(Symbol);

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoBeginProc:=procedure
  begin
    Client.SendRequestForging(Owner,TokenID,Port,BuyAmount,PayAmount,Ratio,
      Commission1,Commission2);
  end;

  if Port='' then
    DoExcept('forbidden coin')
  else
    DoConnection;

  end);

end;

procedure TCloudCore.SendRequestCreateOffer(Direction: Integer; const Symbol1,Symbol2: string;
  Amount,Ratio: Extended; EndDate: TDateTime);
begin

  Enqueue('SendRequestCreateOffer',procedure
  var Coin1,Coin2: Integer;
  begin

  ToLog('Execute request create offer '+Symbol1+'-'+Direction.ToString+'->'+Symbol2+' '+
    'Amount='+AmountToStr(Amount)+' Ratio='+AmountToStr(Ratio));

  UI.WaitLock;

  Coin1:=SymbolID(Symbol1,0);
  Coin2:=SymbolID(Symbol2,0);

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoCreateOfferProc:=procedure
  begin
    try
      AppCore.DoOfferTransfer(Direction,Symbol1,Symbol2,OfferAccount,Amount,Ratio);
      Client.SendRequestCreateOffer(Direction,Coin1,Coin2,Amount,Ratio,EndDate);
    except on E: Exception do
      DoExcept(E.Message);
    end;
  end;

  if OfferAccount=0 then
  begin

    DoBeginProc:=procedure
    begin
      Client.SendRequestOfferAccount;
    end;

    DoOfferAccountProc:=procedure(AccountID: Integer)
    begin
      OfferAccount:=AccountID;
      DoCreateOfferProc;
    end;

  end else

    DoBeginProc:=DoCreateOfferProc;

  if (Coin1=0) or (Coin2=0) then
    DoExcept('forbidden coin')
  else
    DoConnection;

  end);

end;

procedure TCloudCore.SendRequestOffers(const Symbol1,Symbol2: string);
begin

  Enqueue('SendRequestOffers',procedure
  begin

  ToLog('Execute request offers list');

  UI.WaitLock;

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoBeginProc:=procedure
  begin
    Client.SendRequestOffers(SymbolID(Symbol1),SymbolID(Symbol2));
  end;

  DoConnection;

  end);

end;

procedure TCloudCore.SendRequestKillOffers(const Offers: TArray<Int64>);
begin

  Enqueue('SendRequestKillOffer',procedure
  begin

//  ToLog('Execute request kill offer id='+Cloud.Utils.ToString(Offers,', '));

  UI.WaitLock;

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoBeginProc:=procedure
  begin
    Client.SendRequestKillOffers(Offers);
  end;

  DoConnection;

  end);

end;

procedure TCloudCore.SendRequestActiveOffer;
begin

  Enqueue('SendRequestActiveOffer',procedure
  begin

  ToLog('Execute request active offers list');

  UI.WaitLock;

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoBeginProc:=procedure
  begin
    Client.SendRequestActiveOffers;
  end;

  DoConnection;

  end);

end;

procedure TCloudCore.SendRequestClosedOffer(BeginDate,EndDate: TDateTime);
begin

  Enqueue('SendRequestClosedOffer',procedure
  begin

  ToLog('Execute request closed offers list');

  UI.WaitLock;

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoBeginProc:=procedure
  begin
    Client.SendRequestClosedOffers(BeginDate,EndDate);
  end;

  DoConnection;

  end);

end;

procedure TCloudCore.SendRequestHistoryOffer(BeginDate,EndDate: TDateTime);
begin

  Enqueue('SendRequestHistoryOffer',procedure
  begin

  ToLog('Execute request offers history list');

  UI.WaitLock;

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoBeginProc:=procedure
  begin
    Client.SendRequestHistoryOffers(BeginDate,EndDate);
  end;

  DoConnection;

  end);

end;

procedure TCloudCore.SendRequestPairsSummary;
begin

  Enqueue('SendRequestPairsSummary',procedure
  begin

  ToLog('Execute request pairs summary list');

  UI.WaitLock;

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoBeginProc:=procedure
  begin
    Client.SendRequestPairsSummary;
  end;

  DoConnection;

  end);

end;

procedure TCloudCore.SendRequestCandles(const Symbol1,Symbol2: string;
  BeginDate: TDateTime; IntervalType: Integer);
begin

  Enqueue('SendRequestCandles',procedure
  begin

  ToLog('Execute request candles data '+Symbol1+'/'+Symbol2);

  UI.WaitLock;

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoBeginProc:=procedure
  begin
    Client.SendRequestCandles(SymbolID(Symbol1),SymbolID(Symbol2),BeginDate,IntervalType);
  end;

  DoConnection;

  end);

end;

procedure TCloudCore.SendRequestSetNotifications(Enabled: Boolean);
begin

  Enqueue('SendRequestSetNotifications',procedure
  begin

  ToLog('Execute request set notifications');

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoBeginProc:=procedure
  begin
    Client.SendRequestSetNotifications(Enabled);
  end;

  DoConnection;

  end);

end;

procedure TCloudCore.SendRequestTradingHistory(const Symbol1,Symbol2: string; Count: Integer);
begin

  Enqueue('SendRequestTradingHistory',procedure
  begin

  ToLog('Execute request trading history');

  DoConnectProc:=DoLoginProc;

  DoErrorProc:=DoErrorProcDefault;

  DoBeginProc:=procedure
  begin
    Client.SendRequestTradingHistory(SymbolID(Symbol1),SymbolID(Symbol2),Count);
  end;

  DoConnection;

  end);

end;

end.
