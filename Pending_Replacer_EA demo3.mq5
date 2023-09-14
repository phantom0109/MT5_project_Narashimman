//+------------------------------------------------------------------+
//|                                              Pending_Replacer_EA |
//|                                        Created by Narashimman_Fx |
//|                                        narashimman95fx@gmail.com |
//+------------------------------------------------------------------+


#property copyright "Copyright © 2023, Created by Narashimman_Fx"
#property link      "https://t.me/Narashimman_Fx"
#property description ""
#property strict


#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\DealInfo.mqh>

CPositionInfo  m_position;
CTrade         m_trade;
CDealInfo      m_deal;


// exported variables

input bool     Filter_Comment       =  false;         //Use Comments Filter
input string   Comment_Str          =  "";            //Filter Text
input int      Magic_Number         =  4667780;       //Magic Number
input int      Slippage             =  5;             //Slippage



// local variables

double PipValue = 0.00001;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(AccountInfoInteger(ACCOUNT_TRADE_EXPERT) == false)
     {
      Print("Check terminal options because EA trade option is set to not allowed.");
      Alert("Check terminal options because EA trade option is set to not allowed.");
     }

   m_trade.SetDeviationInPoints(Slippage);
   m_trade.SetExpertMagicNumber(Magic_Number);
   
   PipValue = Point();
   
   return(INIT_SUCCEEDED);
  }
  
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  
  }



struct Trade_Data
{
   ulong tic;
   int typ;
   string sym;
   double lot;
   double price;
   double sl;
   double tp;
   string cmt;
   
};


Trade_Data Trades[];

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{

//---
   
   Record_Pendings();
   
   bool res = Check_Pendings();
   
   if (PositionsTotal() ==0 && OrdersTotal() ==0 && res) ArrayResize(Trades,0,100);
}



void Record_Pendings()
{
   for (int i=0; i<OrdersTotal(); i++)
     {
      ulong tic = OrderGetTicket(i);
      bool ret = OrderSelect(tic);
      
      ulong pos_id = OrderGetInteger(ORDER_POSITION_ID);
      string sym = OrderGetString(ORDER_SYMBOL);
      int typ = (int)OrderGetInteger(ORDER_TYPE);
      string cmt = OrderGetString(ORDER_COMMENT);
      
      if (ret && tic >0 && sym==Symbol() && typ >1 && typ <6
                  && (!Filter_Comment || StringFind(cmt,Comment_Str) >=0) )
        {
         bool found1 = false;
         
         for (int t=0; t<ArraySize(Trades); t++)
           {
            if (Trades[t].tic == tic)
              {
               found1 = true;
               
               break;
              }
           }
           
         if (!found1)
           {
            int s = ArraySize(Trades);
            ArrayResize(Trades,s+1,100);
            
            Trades[s].tic = tic;
            Trades[s].sym = sym;
            Trades[s].typ = typ;
            Trades[s].lot = OrderGetDouble(ORDER_VOLUME_CURRENT);
            Trades[s].price = OrderGetDouble(ORDER_PRICE_OPEN);
            Trades[s].sl = OrderGetDouble(ORDER_SL);
            Trades[s].tp = OrderGetDouble(ORDER_TP);
            Trades[s].cmt = cmt;
            
            Print("Order #", Trades[s].tic, " added to EA list");
           }
        }
         
     }
   
}


bool Check_Pendings()
{
   bool pass = true;
   
   for (int i=0; i<ArraySize(Trades); i++)
     {
      if (Trades[i].tic >0 && (!Filter_Comment || StringFind(Trades[i].cmt,Comment_Str) >=0) && IsSL(Trades[i].tic))
        {
         double ask = SymbolInfoDouble(Trades[i].sym,SYMBOL_ASK);
         double bid = SymbolInfoDouble(Trades[i].sym,SYMBOL_BID);
         
         int typ = Trades[i].typ;
         
         double stops = MathMax(SymbolInfoInteger(Trades[i].sym,SYMBOL_TRADE_STOPS_LEVEL),
                        SymbolInfoInteger(Trades[i].sym,SYMBOL_TRADE_FREEZE_LEVEL)) * SymbolInfoDouble(Trades[i].sym, SYMBOL_POINT);
         
         if ((typ%2 ==0 && MathAbs(Trades[i].price - ask) < stops) || (typ%2 ==1 && MathAbs(Trades[i].price - bid) < stops))
           {
            pass = false;
            continue;
           }
         
         if (typ ==2 && Trades[i].price > ask) typ = 4;
         else if (typ ==3 && Trades[i].price < bid) typ = 5;
         else if (typ ==4 && Trades[i].price < ask) typ = 2;
         else if (typ ==5 && Trades[i].price > bid) typ = 3;
         
         bool res = m_trade.OrderOpen(Trades[i].sym, (ENUM_ORDER_TYPE)typ, LotNormalize(Trades[i].lot,Trades[i].sym), 0,
                                       Trades[i].price, Trades[i].sl, Trades[i].tp, 0, 0, Trades[i].cmt);
         
         ulong tic = 0;
         
         if (res)
           {
            do tic = m_trade.ResultOrder();
            while (!OrderSelect(tic));
            
            ulong old_tic = Trades[i].tic;
            
            bool ret = OrderSelect(tic);
            Trades[i].tic = tic; //OrderGetInteger(ORDER_POSITION_ID);
            
            Print("Order #", old_tic, " replaced by #", Trades[i].tic);
           }
         else if (!res)
           {
            pass = false;
            Print("OrderSend() error - ", GetLastError());
           }
         
        }
         
     }
   
   return(pass);  
}


bool IsSL(ulong tic1)
{
   if (tic1 >0 && !PositionSelectByTicket(tic1))
     {
      HistorySelectByPosition(tic1);
      
      for(int t=0; t<HistoryDealsTotal(); t++)
        {
         ulong tic = HistoryDealGetTicket(t);
         ulong entry = HistoryDealGetInteger(tic,DEAL_ENTRY);
         string cmt = HistoryDealGetString(tic,DEAL_COMMENT);
         
         if (entry==DEAL_ENTRY_OUT && StringFind(cmt,"[sl ")>=0) return (true);
        }
      
     }
     
   return false;   
}



double LotNormalize(double lots, string sym="")
  {
   if (sym=="") sym = Symbol();
   
   double lstep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lmax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(lstep>0)
      lots = MathRound(lots/lstep) * lstep;

   if(lots<lmin)
      lots = lmin;
   if(lots>lmax)
      lots = lmax;
   return(lots);
  }

