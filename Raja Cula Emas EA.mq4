//+------------------------------------------------------------------+
//|                                                       SimpleEA.mq4|
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                       https://www.mql4.com       |
//+------------------------------------------------------------------+
#property strict

// Input parameters
input double TakeProfit = 50;                    // Take Profit in points
input double StopLoss = 0;                       // Stop Loss in points (0 means no SL)
input double LotSize = 0.1;                      // Lot size
input int MaxOpenOrders = 5;                     // Maximum number of open orders
input int StartHour = 8;                         // Trading start hour (UTC+7)
input int EndHour = 16;                          // Trading end hour (UTC+7)
input bool EnableSupportResistance = true;       // Enable Support/Resistance Strategy
input bool EnableMovingAverage = true;           // Enable Moving Average Strategy
input bool EnableBullishBearishEngulfing = true; // Enable Bullish/Bearish Engulfing
input bool EnableTrendBandsStrategy = true;      // Enable Trend Bands Strategy
input bool EnableEMAStrategy = true;             // Enable EMA Strategy
input bool EnableMACDStrategy = true;            // Enable MACD Strategy
input bool EnableVolumeStrategy = true;          // Enable Volume Strategy
input bool EnableMoneyManagement = true;         // Enable Money Management
input double DailyLossLimitPercent = 50.0;       // Daily loss limit as a percentage of starting balance
input double DailyProfitTarget = 100.0;          // Daily profit target in account currency (USD, EUR, etc.)

// Global variables
int lossCount = 0;                          // Counter for consecutive losses
datetime lastTradeDate = 0;                 // Last trade date
double dailyStartingBalance = 0;            // Starting balance of the day
double dailyLossLimit = 0;                  // Daily loss limit
double dailyProfit = 0;                     // Daily profit tracker

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    dailyStartingBalance = AccountBalance();
    dailyLossLimit = dailyStartingBalance * (DailyLossLimitPercent / 100.0);
    dailyProfit = 0; // Initialize daily profit to 0
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Function to calculate dynamic lot size based on balance          |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    if (EnableMoneyManagement)
    {
        // Calculate lot size based on balance with 0.01 lot per $50
        double balance = AccountBalance();
        double calculatedLotSize = 0.01 + 0.02 * MathFloor(balance / 300.0);

        return NormalizeDouble(calculatedLotSize, 2);
        
        // Ensure lot size is within broker's allowable limits
        double minLot = MarketInfo(Symbol(), MODE_MINLOT);
        double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
        return MathMax(MathMin(calculatedLotSize, maxLot), minLot); // Set to two decimal places for precision
    }
    else
    {
        // Use manually set LotSize
        return LotSize;
    }
}

//+------------------------------------------------------------------+
//| Function to calculate support and resistance                     |
//+------------------------------------------------------------------+
void CalculateSupportResistance(double &support, double &resistance)
{
    double highestHigh = High[0];
    double lowestLow = Low[0];
    
    for (int i = 1; i < 14; i++)
    {
        if (High[i] > highestHigh)
            highestHigh = High[i];
        if (Low[i] < lowestLow)
            lowestLow = Low[i];
    }

    resistance = highestHigh;
    support = lowestLow;
}

//+------------------------------------------------------------------+
//| Function to calculate Trend Bands                                |
//+------------------------------------------------------------------+
void CalculateTrendBands(double &upperBand, double &lowerBand)
{
    int period = 34;
    double bandMultiplier = 2.0;

    double ma = iMA(Symbol(), 0, period, 0, MODE_SMA, PRICE_CLOSE, 0);
    double stdDev = iStdDev(Symbol(), 0, period, 0, MODE_SMA, PRICE_CLOSE, 0);

    upperBand = ma + bandMultiplier * stdDev;
    lowerBand = ma - bandMultiplier * stdDev;
}

//+------------------------------------------------------------------+
//| Function to update Trend Bands lines                             |
//+------------------------------------------------------------------+
void UpdateTrendBandsLines(double upperBand, double lowerBand)
{
    static int upperBandLine = 0;
    static int lowerBandLine = 0;

    if (upperBandLine == 0)
        upperBandLine = ObjectCreate("UpperBand", OBJ_HLINE, 0, Time[0], upperBand);
    if (lowerBandLine == 0)
        lowerBandLine = ObjectCreate("LowerBand", OBJ_HLINE, 0, Time[0], lowerBand);

    ObjectSet("UpperBand", OBJPROP_PRICE1, upperBand);
    ObjectSet("UpperBand", OBJPROP_COLOR, clrBlue);

    ObjectSet("LowerBand", OBJPROP_PRICE1, lowerBand);
    ObjectSet("LowerBand", OBJPROP_COLOR, clrRed);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime currentTime = TimeCurrent() + 7 * 3600; // Convert to UTC+7
    int currentHour = TimeHour(currentTime);
    int currentDay = TimeDay(currentTime);
    int currentMonth = TimeMonth(currentTime);
    int currentYear = TimeYear(currentTime);
    datetime currentDate = StrToTime(IntegerToString(currentYear) + "." + 
                                       IntegerToString(currentMonth) + "." + 
                                       IntegerToString(currentDay));

    // Cek apakah waktu trading valid
    if (currentHour < StartHour || currentHour >= EndHour)
        return;

    // Reset daily starting balance dan loss limit di awal setiap hari
    if (currentDate != lastTradeDate)
    {
        lastTradeDate = currentDate;
        dailyStartingBalance = AccountBalance();
        dailyLossLimit = dailyStartingBalance * (DailyLossLimitPercent / 100.0);
        dailyProfit = 0; // Reset profit harian saat pergantian hari
        lossCount = 0;
    }

    // Cek apakah target profit harian tercapai
    if (dailyProfit >= DailyProfitTarget)
    {
        Print("Daily profit target reached. No further trades will be made today.");
        return; // Hentikan trading jika target profit tercapai
    }

    // Cek daily loss limit
    if ((dailyStartingBalance - AccountBalance()) >= dailyLossLimit)
    {
        Print("Daily loss limit reached. No further trades will be made today.");
        return;
    }

    // Hitung Support/Resistance
    double support = 0, resistance = 0;
    if (EnableSupportResistance)
        CalculateSupportResistance(support, resistance);

    double lastClose = Close[1];
    int openOrdersCount = 0;
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == Symbol())
        {
            openOrdersCount++;
        }
    }

    // Tentukan lot size berdasarkan money management
    double lotSize = CalculateLotSize();

    // Kondisi untuk setiap strategi
    bool supportResistanceBuySignal = (EnableSupportResistance && lastClose <= support);
    bool supportResistanceSellSignal = (EnableSupportResistance && lastClose >= resistance);

    double upperBand = 0, lowerBand = 0;
    bool trendBandsBuySignal = false, trendBandsSellSignal = false;
    if (EnableTrendBandsStrategy) 
    {
        CalculateTrendBands(upperBand, lowerBand);
        UpdateTrendBandsLines(upperBand, lowerBand);
        trendBandsBuySignal = (lastClose <= lowerBand);
        trendBandsSellSignal = (lastClose >= upperBand);
    }

    double ma = 0;
    bool maBuySignal = false, maSellSignal = false;
    if (EnableMovingAverage)
    {
        ma = iMA(Symbol(), 0, 50, 0, MODE_SMA, PRICE_CLOSE, 1);
        maBuySignal = (lastClose > ma);
        maSellSignal = (lastClose < ma);
    }

    bool engulfingBuySignal = false, engulfingSellSignal = false;
    if (EnableBullishBearishEngulfing)
    {
        engulfingBuySignal = (Close[1] > Open[1] && Close[2] < Open[2] && Close[1] > Open[2]);
        engulfingSellSignal = (Close[1] < Open[1] && Close[2] > Open[2] && Close[1] < Open[2]);
    }

    double ema = 0;
    bool emaBuySignal = false, emaSellSignal = false;
    if (EnableEMAStrategy)
    {
        ema = iMA(Symbol(), 0, 50, 0, MODE_EMA, PRICE_CLOSE, 1);
        emaBuySignal = (lastClose > ema);
        emaSellSignal = (lastClose < ema);
    }

    double macdMain = 0, macdSignal = 0;
    bool macdBuySignal = false, macdSellSignal = false;
    if (EnableMACDStrategy)
    {
        macdMain = iMACD(Symbol(), 0, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0);
        macdSignal = iMACD(Symbol(), 0, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 0);
        macdBuySignal = (macdMain > macdSignal);
        macdSellSignal = (macdMain < macdSignal);
    }

    bool volumeBuySignal = false, volumeSellSignal = false;
    if (EnableVolumeStrategy)
    {
        volumeBuySignal = (Volume[0] > Volume[1]);
        volumeSellSignal = (Volume[0] < Volume[1]);
    }

    // Eksekusi Buy order jika ada Buy Signal
    if ((supportResistanceBuySignal || trendBandsBuySignal || maBuySignal || engulfingBuySignal || emaBuySignal || macdBuySignal || volumeBuySignal) &&
        openOrdersCount < MaxOpenOrders && lossCount < 3)
    {
        double price = NormalizeDouble(Ask, Digits);
        double tp = NormalizeDouble(price + TakeProfit * Point, Digits);
        double sl = (StopLoss > 0) ? NormalizeDouble(price - StopLoss * Point, Digits) : 0;

        int ticket = OrderSend(Symbol(), OP_BUY, lotSize, price, 2, sl, tp, "Buy Order", 0, 0, clrGreen);
        if (ticket < 0)
        {
            Print("Error opening buy order: ", GetLastError());
        }
    }

    // Eksekusi Sell order jika ada Sell Signal
    if ((supportResistanceSellSignal || trendBandsSellSignal || maSellSignal || engulfingSellSignal || emaSellSignal || macdSellSignal || volumeSellSignal) &&
        openOrdersCount < MaxOpenOrders && lossCount < 3)
    {
        double price = NormalizeDouble(Bid, Digits);
        double tp = NormalizeDouble(price - TakeProfit * Point, Digits);
        double sl = (StopLoss > 0) ? NormalizeDouble(price + StopLoss * Point, Digits) : 0;

        int ticket = OrderSend(Symbol(), OP_SELL, lotSize, price, 2, sl, tp, "Sell Order", 0, 0, clrRed);
        if (ticket < 0)
        {
            Print("Error opening sell order: ", GetLastError());
        }
    }

    // Cek untuk menghitung profit harian
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == Symbol())
        {
            // Menghitung profit dari order yang sudah tertutup
            if (OrderCloseTime() > lastTradeDate) // Jika order ditutup pada hari ini
            {
                dailyProfit += OrderProfit(); // Tambahkan profit dari order ke total profit harian
            }
        }
    }
}
