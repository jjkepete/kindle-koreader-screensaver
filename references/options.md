# 参数与版式参考

## 一、CFG 全参数

生成的 `2-blbscreen.lua` 顶部有一段 `local CFG = { ... }`，改完存盘、重启 KOReader 即生效。
也可以重新跑 `build_patch.py` 覆盖生成。

| 键 | 取值 | 说明 |
|---|---|---|
| `wake_enabled` | true / false | 关掉即"入睡定格"，零耗电 |
| `wake_interval_min` | 0 / 30 / 60 | 0 = 对齐整点（走时最准）；>0 = 固定间隔分钟 |
| `wake_hour_min` | 0–23 | 最早唤醒整点，含 |
| `wake_hour_max` | 0–23 | 最晚唤醒整点，含 |
| `weather_enabled` | true / false | 关掉则完全不联网 |
| `weather_lat` / `weather_lon` | 字符串 | 纬度 / 经度，用城市名查 Open-Meteo 地理编码 |
| `weather_days` | 1 / 2 / 3 | 天气列数 |
| `weather_city` | 字符串 | 只写进日志，不上屏 |
| `quote_source` | builtin / custom / off | 短句来源 |
| `quote_custom_file` | 路径字符串 | 留空则用 `plugins/blbscreen.koplugin/quotes.txt` |
| `show_header` | bool | 页眉：干支 + 年内第几天 |
| `show_clock` | bool | 大号时:分 |
| `show_date` | bool | 公历年月日 + 星期 |
| `show_week` | bool | 本周七天，今天高亮 |
| `show_lunar` | bool | 农历 + 干支生肖 |
| `show_huangli` | bool | 宜 / 忌两行 |
| `show_quote` | bool | 短句 |
| `show_footer` | bool | 底部"按电源键唤醒" |
| `font_scale` | 0.9–1.15 | 整体字号倍率 |

## 二、版式坐标（1024 高基准）

所有纵坐标以 1024px 高为设计基准，实际屏幕按 `VSCALE = 屏幕高 / 1024` 等比缩放。

| 区块 | 基线 y | 关掉后的上移量 |
|---|---|---|
| 页眉分隔线 | 60 | 46 |
| 时:分 | 230 | 134 |
| 公历日期 | 300 | 70 |
| 周历标签 / 数字 | 366 / 421 | 106 |
| 农历 + 干支 | 508 / 560 | 52 |
| 宜 / 忌 | 604 / 650 | 144 |
| 天气 | 748 / 790 / 818 | 118 |
| 短句 | 908（两行）/ 924（一行） | 70 |
| 页脚 | 992 | — |

左右边距 `M = 52`（同样缩放）。

## 三、机型适配

不需要改坐标，补丁按屏幕高自动缩放。已知机型的缩放系数：

| 机型 | 分辨率 | 比例 | 缩放系数 |
|---|---|---|---|
| Kindle 4/5 (K4/K5) | 600×800 | 0.750 | 0.78 |
| Paperwhite 1/2 | 758×1024 | 0.740 | 1.00 |
| Paperwhite 3/4 | 1072×1448 | 0.740 | 1.41 |
| Paperwhite 5 (11th) | 1236×1648 | 0.750 | 1.61 |
| Voyage | 1072×1448 | 0.740 | 1.41 |
| Oasis 1/2/3 | 1264×1680 | 0.752 | 1.64 |
| Kindle Basic 10th/11th | 600×800 / 1072×1448 | — | 0.78 / 1.41 |

比例都在 0.74–0.75，等比缩放不会变形。极端非 4:3 比例的设备需要单独调。

## 四、想加一个新元素

按这个顺序做，避免返工：

1. **定数据源**：本地表（像 `huangli.lua`）/ 联网（像天气）/ 读用户文件（像 `quotes.txt`）。
2. **定刷新时机**：跟随每次休眠重绘，还是跟着定时唤醒一起刷。联网数据一律走"阅读时预热 + 休眠只读缓存"，
   唤醒窗口内不联网，否则每次唤醒都要拉起 Wi-Fi，耗电翻几倍。
3. **挂坐标**：在 `paint()` 里按 `Y(基准y) - off` 取位置，用 `getFace(字号)` 取字体。
   新增区块要把后续区块的 `off` 加上它的高度，否则会叠在一起。
4. **写降级**：数据缺失时画 `--` 或直接跳过该块（并同样累加 `off`）。
5. **算高度**：可用高度 = 1024，各区块高度见上表。新块挤不下时，先让用户选"挤掉哪个"或"缩字号"。

## 五、天气源

Open-Meteo，免费、免 key、无需注册：

```
https://api.open-meteo.com/v1/forecast?latitude=24.78&longitude=118.55
  &current=temperature_2m,weather_code
  &daily=weather_code,temperature_2m_max,temperature_2m_min
  &timezone=Asia%2FShanghai&forecast_days=3
```

城市名的经度纬度用地理编码接口查：

```
https://geocoding-api.open-meteo.com/v1/search?name=泉州&count=1&language=zh
```

返回里的 `latitude` / `longitude` 直接填进 CFG。

天气代码（WMO）到中文的映射在补丁的 `WMO` 表里，遇到没翻译的代码会退回"多云"。

## 六、句库文件格式

`quotes.txt`：UTF-8 编码，一行一句，`#` 开头为注释，空行忽略。

```
# 我的句子
慢一点没关系，方向对了，路会越走越短。
今天把该做的事做完，明天就轻一点。
```

轮换规则按日期算：`(年 × 372 + 年内第几天) % 句数`，所以同一天永远显示同一句，跨天自动换。
句数少于 5 句时，几天内会重复，交付时提醒用户一句。
