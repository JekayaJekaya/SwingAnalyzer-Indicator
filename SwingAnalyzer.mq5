#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

// Входные параметры индикатора
input int LookbackBars = 150;      // Количество баров для анализа
input int SwingLookbackBars = 2;   // Количество баров для определения свингов

// Глобальная переменная для отслеживания времени последнего обработанного бара
datetime g_lastBarTime = 0;

// Перечисления для типов свингов и тренда
enum SwingType {
   SWING_HH,  // Higher High
   SWING_HL,  // Higher Low
   SWING_LH,  // Lower High
   SWING_LL,  // Lower Low
   SWING_SH,  // Swing High (начальная точка)
   SWING_SL   // Swing Low (начальная точка)
};

enum TrendType {
   TREND_LONG,   // Бычий тренд
   TREND_SHORT,  // Медвежий тренд
   TREND_NONE    // Тренд не определён
};

// Структура для хранения информации о свинге
struct SwingPoint {
   int barIndex;      // Индекс бара
   double price;      // Цена свинга
   SwingType type;    // Тип свинга (HH, HL, LH, LL, SH, SL)
   bool isHigh;       // true = Swing High, false = Swing Low
};

// Класс для рисования свингов и линий пробоя на графике
class SwingVisualizer {
private:
   string objectPrefix; // Префикс для имен объектов

public:
   SwingVisualizer(string prefix) : objectPrefix(prefix) {}

   // Очистка всех объектов на графике
   void ClearObjects() {
      for (int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--) {
         string objName = ObjectName(0, i);
         if (StringFind(objName, objectPrefix) == 0) {
            ObjectDelete(0, objName);
         }
      }
   }

   // Рисование Swing High с меткой
   void DrawSwingHigh(int bar, double price, const datetime &time[], string label, color clr) {
      string objName = objectPrefix + "High_" + IntegerToString(bar);
      ObjectDelete(0, objName);
      ObjectCreate(0, objName, OBJ_TEXT, 0, time[bar], price + 20 * Point());
      ObjectSetString(0, objName, OBJPROP_TEXT, label);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 8);
   }

   // Рисование Swing Low с меткой
   void DrawSwingLow(int bar, double price, const datetime &time[], string label, color clr) {
      string objName = objectPrefix + "Low_" + IntegerToString(bar);
      ObjectDelete(0, objName);
      ObjectCreate(0, objName, OBJ_TEXT, 0, time[bar], price - 20 * Point());
      ObjectSetString(0, objName, OBJPROP_TEXT, label);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 8);
   }

   // Рисование линии пробоя тренда
   void DrawBreakoutLine(int startBar, double startPrice, int endBar, const datetime &time[], color clr, string trendLabel) {
      string objName = objectPrefix + "Breakout_" + IntegerToString(startBar) + "_" + IntegerToString(endBar);
      ObjectDelete(0, objName);
      ObjectCreate(0, objName, OBJ_TREND, 0, time[startBar], startPrice, time[endBar], startPrice);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objName, OBJPROP_RAY, false);

      string textName = objectPrefix + "TrendLabel_" + IntegerToString(endBar);
      ObjectDelete(0, textName);
      ObjectCreate(0, textName, OBJ_TEXT, 0, time[endBar], startPrice + 40 * Point());
      ObjectSetString(0, textName, OBJPROP_TEXT, trendLabel);
      ObjectSetInteger(0, textName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
   }
};

// Класс для анализа свингов и трендов
class SwingAnalyzer {
private:
   SwingVisualizer visualizer; // Объект для рисования
   int lookbackBars;          // Глубина анализа (в барах)
   int swingLookbackBars;     // Количество баров для определения свингов
   SwingPoint swings[];       // Массив свингов
   TrendType trendHistory[];  // История тренда для каждого бара

   // Проверка, является ли бар Swing High
   bool IsSwingHigh(int bar, const double &high[], int rates_total) {
      if (bar < swingLookbackBars || bar >= rates_total) return false;

      double currentHigh = high[bar];
      bool isHigh = true;
      for (int i = 1; i <= swingLookbackBars; i++) {
         if (bar - i >= 0 && high[bar - i] >= currentHigh) {
            isHigh = false;
            break;
         }
         if (bar + i < rates_total && high[bar + i] >= currentHigh) {
            isHigh = false;
            break;
         }
      }
      return isHigh;
   }

   // Проверка, является ли бар Swing Low
   bool IsSwingLow(int bar, const double &low[], int rates_total) {
      if (bar < swingLookbackBars || bar >= rates_total) return false;

      double currentLow = low[bar];
      bool isLow = true;
      for (int i = 1; i <= swingLookbackBars; i++) {
         if (bar - i >= 0 && low[bar - i] <= currentLow) {
            isLow = false;
            break;
         }
         if (bar + i < rates_total && low[bar + i] <= currentLow) {
            isLow = false;
            break;
         }
      }
      return isLow;
   }

   // Добавление промежуточной точки (например, HL между двумя HH)
   void AddIntermediateSwing(int prevBar, int currBar, bool isHigh, const double &high[], const double &low[], 
                             int &lastLowerHighBar, double &lastLowerHighPrice, 
                             int &lastHigherLowBar, double &lastHigherLowPrice) {
      if (currBar - prevBar <= 1) return;

      int swingCount = ArraySize(swings);
      ArrayResize(swings, swingCount + 1);

      if (isHigh) { // Два Swing High подряд → добавляем Swing Low
         int minLowBar = prevBar + 1;
         double minLowPrice = low[minLowBar];
         for (int bar = prevBar + 1; bar < currBar; bar++) {
            if (low[bar] < minLowPrice) {
               minLowPrice = low[bar];
               minLowBar = bar;
            }
         }
         swings[swingCount].barIndex = minLowBar;
         swings[swingCount].price = minLowPrice;
         swings[swingCount].type = SWING_HL; // Тип будет уточнён позже
         swings[swingCount].isHigh = false;
         lastHigherLowBar = minLowBar;
         lastHigherLowPrice = minLowPrice;
      }
      else { // Два Swing Low подряд → добавляем Swing High
         int maxHighBar = prevBar + 1;
         double maxHighPrice = high[maxHighBar];
         for (int bar = prevBar + 1; bar < currBar; bar++) {
            if (high[bar] > maxHighPrice) {
               maxHighPrice = high[bar];
               maxHighBar = bar;
            }
         }
         swings[swingCount].barIndex = maxHighBar;
         swings[swingCount].price = maxHighPrice;
         swings[swingCount].type = SWING_HH; // Тип будет уточнён позже
         swings[swingCount].isHigh = true;
         lastLowerHighBar = maxHighBar;
         lastLowerHighPrice = maxHighPrice;
      }
   }

   // Проверка пробоя тренда
   void CheckForTrendBreakout(int bar, const double &high[], const double &low[], 
                              bool &isBullishTrend, int lastLowerHighBar, double lastLowerHighPrice, 
                              int lastHigherLowBar, double lastHigherLowPrice, 
                              const datetime &time[]) {
      if (isBullishTrend && lastHigherLowBar != -1 && bar > lastHigherLowBar) {
         if (low[bar] < lastHigherLowPrice) {
            isBullishTrend = false;
            visualizer.DrawBreakoutLine(lastHigherLowBar, lastHigherLowPrice, bar, time, clrYellow, "Short");
         }
      }
      else if (!isBullishTrend && lastLowerHighBar != -1 && bar > lastLowerHighBar) {
         if (high[bar] > lastLowerHighPrice) {
            isBullishTrend = true;
            visualizer.DrawBreakoutLine(lastLowerHighBar, lastLowerHighPrice, bar, time, clrYellow, "Long");
         }
      }
   }

   // Определение свингов
   void DetectSwings(int startBar, int endBar, const double &high[], const double &low[], 
                     int rates_total, bool trendDefined, bool &isBullishTrend, 
                     int &lastHighSwingBar, int &lastLowSwingBar, 
                     int &lastLowerHighBar, double &lastLowerHighPrice, 
                     int &lastHigherLowBar, double &lastHigherLowPrice, 
                     const datetime &time[]) {
      for (int bar = endBar; bar <= startBar; bar++) {
         // Проверяем пробой тренда
         if (trendDefined) {
            CheckForTrendBreakout(bar, high, low, isBullishTrend, 
                                  lastLowerHighBar, lastLowerHighPrice, 
                                  lastHigherLowBar, lastHigherLowPrice, time);
         }

         // Обновляем историю тренда для текущего бара
         if (trendDefined) {
            trendHistory[bar] = isBullishTrend ? TREND_LONG : TREND_SHORT;
         }

         bool isSwingHigh = IsSwingHigh(bar, high, rates_total);
         bool isSwingLow = IsSwingLow(bar, low, rates_total);

         if (!trendDefined) continue;

         if (isSwingHigh) {
            SwingType swingType = isBullishTrend ? SWING_HH : SWING_LH;
            if (lastHighSwingBar != -1) {
               AddIntermediateSwing(lastHighSwingBar, bar, true, high, low, 
                                    lastLowerHighBar, lastLowerHighPrice, 
                                    lastHigherLowBar, lastHigherLowPrice);
            }
            lastHighSwingBar = bar;
            lastLowerHighBar = bar;
            lastLowerHighPrice = high[bar];

            int swingCount = ArraySize(swings);
            ArrayResize(swings, swingCount + 1);
            swings[swingCount].barIndex = bar;
            swings[swingCount].price = high[bar];
            swings[swingCount].type = swingType;
            swings[swingCount].isHigh = true;
         }
         if (isSwingLow) {
            SwingType swingType = isBullishTrend ? SWING_HL : SWING_LL;
            if (lastLowSwingBar != -1) {
               AddIntermediateSwing(lastLowSwingBar, bar, false, high, low, 
                                    lastLowerHighBar, lastLowerHighPrice, 
                                    lastHigherLowBar, lastHigherLowPrice);
            }
            lastLowSwingBar = bar;
            lastHigherLowBar = bar;
            lastHigherLowPrice = low[bar];

            int swingCount = ArraySize(swings);
            ArrayResize(swings, swingCount + 1);
            swings[swingCount].barIndex = bar;
            swings[swingCount].price = low[bar];
            swings[swingCount].type = swingType;
            swings[swingCount].isHigh = false;
         }
      }
   }

   // Определение начальных точек и пробоев тренда
   void DetectBreakouts(int startBar, int endBar, const double &high[], const double &low[], 
                        const datetime &time[], int rates_total, 
                        bool &trendDefined, bool &isBullishTrend, 
                        int &lastHighSwingBar, int &lastLowSwingBar, 
                        int &lastLowerHighBar, double &lastLowerHighPrice, 
                        int &lastHigherLowBar, double &lastHigherLowPrice) {
      int point1Bar = -1, point2Bar = -1;
      double point1Price = 0.0, point2Price = 0.0;
      bool point1IsHigh = false;
      bool pointsDefined = false;
      bool breakoutFound = false;

      for (int bar = endBar; bar <= startBar; bar++) {
         // Проверяем пробой начальных точек
         if (pointsDefined && !breakoutFound) {
            if (point1IsHigh) {
               if (high[bar] > point1Price) {
                  visualizer.DrawBreakoutLine(point1Bar, point1Price, bar, time, clrYellow, "Long");
                  breakoutFound = true;
                  trendDefined = true;
                  isBullishTrend = true;
                  lastLowerHighBar = point1Bar;
                  lastLowerHighPrice = point1Price;
                  lastHigherLowBar = point2Bar;
                  lastHigherLowPrice = point2Price;
               }
               else if (low[bar] < point2Price) {
                  visualizer.DrawBreakoutLine(point2Bar, point2Price, bar, time, clrYellow, "Short");
                  breakoutFound = true;
                  trendDefined = true;
                  isBullishTrend = false;
                  lastLowerHighBar = point1Bar;
                  lastLowerHighPrice = point1Price;
                  lastHigherLowBar = point2Bar;
                  lastHigherLowPrice = point2Price;
               }
            }
            else {
               if (low[bar] < point1Price) {
                  visualizer.DrawBreakoutLine(point1Bar, point1Price, bar, time, clrYellow, "Short");
                  breakoutFound = true;
                  trendDefined = true;
                  isBullishTrend = false;
                  lastLowerHighBar = point2Bar;
                  lastLowerHighPrice = point2Price;
                  lastHigherLowBar = point1Bar;
                  lastHigherLowPrice = point1Price;
               }
               else if (high[bar] > point2Price) {
                  visualizer.DrawBreakoutLine(point2Bar, point2Price, bar, time, clrYellow, "Long");
                  breakoutFound = true;
                  trendDefined = true;
                  isBullishTrend = true;
                  lastLowerHighBar = point2Bar;
                  lastLowerHighPrice = point2Price;
                  lastHigherLowBar = point1Bar;
                  lastHigherLowPrice = point1Price;
               }
            }
         }

         // Обновляем историю тренда для текущего бара
         if (trendDefined) {
            trendHistory[bar] = isBullishTrend ? TREND_LONG : TREND_SHORT;
         }

         // Определяем начальные точки (point1 и point2)
         if (!pointsDefined) {
            bool isSwingHigh = IsSwingHigh(bar, high, rates_total);
            bool isSwingLow = IsSwingLow(bar, low, rates_total);

            if (point1Bar == -1) {
               if (isSwingHigh) {
                  point1Bar = bar;
                  point1Price = high[bar];
                  point1IsHigh = true;
                  int swingCount = ArraySize(swings);
                  ArrayResize(swings, swingCount + 1);
                  swings[swingCount].barIndex = bar;
                  swings[swingCount].price = high[bar];
                  swings[swingCount].type = SWING_SH;
                  swings[swingCount].isHigh = true;
                  lastHighSwingBar = bar;
               }
               else if (isSwingLow) {
                  point1Bar = bar;
                  point1Price = low[bar];
                  point1IsHigh = false;
                  int swingCount = ArraySize(swings);
                  ArrayResize(swings, swingCount + 1);
                  swings[swingCount].barIndex = bar;
                  swings[swingCount].price = low[bar];
                  swings[swingCount].type = SWING_SL;
                  swings[swingCount].isHigh = false;
                  lastLowSwingBar = bar;
               }
            }
            else if (point2Bar == -1) {
               if (point1IsHigh && isSwingLow) {
                  point2Bar = bar;
                  point2Price = low[bar];
                  pointsDefined = true;
                  if (lastLowSwingBar != -1) {
                     AddIntermediateSwing(lastLowSwingBar, bar, false, high, low, 
                                          lastLowerHighBar, lastLowerHighPrice, 
                                          lastHigherLowBar, lastHigherLowPrice);
                  }
                  lastLowSwingBar = bar;
                  int swingCount = ArraySize(swings);
                  ArrayResize(swings, swingCount + 1);
                  swings[swingCount].barIndex = bar;
                  swings[swingCount].price = low[bar];
                  swings[swingCount].type = SWING_SL;
                  swings[swingCount].isHigh = false;
               }
               else if (!point1IsHigh && isSwingHigh) {
                  point2Bar = bar;
                  point2Price = high[bar];
                  pointsDefined = true;
                  if (lastHighSwingBar != -1) {
                     AddIntermediateSwing(lastHighSwingBar, bar, true, high, low, 
                                          lastLowerHighBar, lastLowerHighPrice, 
                                          lastHigherLowBar, lastHigherLowPrice);
                  }
                  lastHighSwingBar = bar;
                  int swingCount = ArraySize(swings);
                  ArrayResize(swings, swingCount + 1);
                  swings[swingCount].barIndex = bar;
                  swings[swingCount].price = high[bar];
                  swings[swingCount].type = SWING_SH;
                  swings[swingCount].isHigh = true;
               }
            }
         }
      }
   }

   // Рисование свингов с правильным цветом
   void DrawSwings(const datetime &time[]) {
      for (int i = 0; i < ArraySize(swings); i++) {
         int bar = swings[i].barIndex;
         TrendType trendAtBar = trendHistory[bar];
         color clr = (trendAtBar == TREND_LONG) ? clrBlue : clrRed;

         // Уточняем тип для промежуточных свингов
         if (swings[i].type == SWING_HH && trendAtBar != TREND_LONG) {
            swings[i].type = SWING_LH;
         }
         else if (swings[i].type == SWING_HL && trendAtBar != TREND_LONG) {
            swings[i].type = SWING_LL;
         }

         // Преобразуем тип свинга в строку для отображения
         string label;
         switch (swings[i].type) {
            case SWING_HH: label = "HH"; break;
            case SWING_HL: label = "HL"; break;
            case SWING_LH: label = "LH"; break;
            case SWING_LL: label = "LL"; break;
            case SWING_SH: label = "SH"; break;
            case SWING_SL: label = "SL"; break;
         }

         if (swings[i].isHigh) {
            visualizer.DrawSwingHigh(swings[i].barIndex, swings[i].price, time, label, clr);
         }
         else {
            visualizer.DrawSwingLow(swings[i].barIndex, swings[i].price, time, label, clr);
         }
      }
   }

public:
   SwingAnalyzer(int lookback, int swingLookback) 
      : lookbackBars(lookback), swingLookbackBars(swingLookback), visualizer("SMC_") {
      ArrayResize(swings, 0);
      ArrayResize(trendHistory, 0);
   }

   // Основной метод анализа и рисования свингов
   void AnalyzeAndDrawSwings(const int rates_total, const double &high[], const double &low[], 
                             const double &close[], const datetime &time[]) {
      if (rates_total < lookbackBars + swingLookbackBars) return;

      // Пересчёт только на новом баре
      if (time[rates_total - 1] == g_lastBarTime) return;
      g_lastBarTime = time[rates_total - 1];

      // Инициализация
      visualizer.ClearObjects();
      ArrayResize(swings, 0);
      ArrayResize(trendHistory, rates_total);
      for (int i = 0; i < rates_total; i++) {
         trendHistory[i] = TREND_NONE;
      }

      int startBar = rates_total - 1;
      int endBar = rates_total - lookbackBars;

      bool trendDefined = false;
      bool isBullishTrend = false;
      int lastHighSwingBar = -1;
      int lastLowSwingBar = -1;
      int lastLowerHighBar = -1;
      double lastLowerHighPrice = 0.0;
      int lastHigherLowBar = -1;
      double lastHigherLowPrice = 0.0;

      // Первый проход: определяем начальные точки и пробои тренда
      DetectBreakouts(startBar, endBar, high, low, time, rates_total, 
                      trendDefined, isBullishTrend, 
                      lastHighSwingBar, lastLowSwingBar, 
                      lastLowerHighBar, lastLowerHighPrice, 
                      lastHigherLowBar, lastHigherLowPrice);

      // Второй проход: определяем свинги (HH, HL, LH, LL) и продолжаем проверять пробои
      DetectSwings(startBar, endBar, high, low, rates_total, 
                   trendDefined, isBullishTrend, 
                   lastHighSwingBar, lastLowSwingBar, 
                   lastLowerHighBar, lastLowerHighPrice, 
                   lastHigherLowBar, lastHigherLowPrice, time);

      // Третий проход: рисуем свинги с правильным цветом
      DrawSwings(time);
   }
};

// Глобальный объект для работы индикатора
SwingAnalyzer *analyzer;

// Инициализация индикатора
int OnInit() {
   analyzer = new SwingAnalyzer(LookbackBars, SwingLookbackBars);
   return(INIT_SUCCEEDED);
}

// Деинициализация индикатора
void OnDeinit(const int reason) {
   delete analyzer;
}

// Основная функция расчёта индикатора
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[]) {
   analyzer.AnalyzeAndDrawSwings(rates_total, high, low, close, time);
   return(rates_total);
}
