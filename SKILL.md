---
name: kindle-koreader-screensaver
description: 为 Kindle 上的 KOReader 定制休眠屏保（时间、周历、农历干支、黄历宜忌、天气、鸡汤），生成可直接放进 patches/ 目录的 Lua 补丁并给出安装验证步骤。当用户提到 Kindle 屏保、KOReader 屏保、休眠屏保、screensaver、电子书阅读器待机画面、水墨屏时钟/天气/黄历，或想改屏保上的内容与刷新频率时使用。生成前必须先向用户逐项确认刷新方式、天气天数、鸡汤来源、显示区块、所在城市等选项，不要自行假定。
agent_created: true
---

# Kindle KOReader 休眠屏保定制

## 这个 skill 产出什么

一份 `2-blbscreen.lua` 补丁（配套 `huangli.lua` 黄历数据），放进 KOReader 的 `patches/` 目录后，
每次 Kindle 休眠都会在设备端画一张整屏 PNG 当屏保：

- 大号时:分 + 公历日期 + 本周七天（今天高亮框）
- 农历日期、干支生肖、黄历宜忌
- 未来 1–3 天天气（Open-Meteo，免 API key）
- 一句轮换的短句
- 白天可选按整点或固定间隔唤醒重绘，让时间不再"定格在入睡那一刻"

水墨屏的特性决定了：休眠时 CPU 挂起，屏保是入睡瞬间画好的静态图。想让它走时，必须定时唤醒重绘，
代价是待机时间。这个 trade-off 必须让用户自己选，不要替用户决定。

## 强制流程

**不要跳过提问直接生成。** 用户的初始描述几乎不会包含全部参数，缺项会让成品不符预期。

### 第 0 问：先确认设备前提

开工前问清两件事，任一不满足就停下来说清楚：

- 是否**已越狱并装好 KOReader**（未越狱只能用系统屏保，本 skill 不适用）
- 是否为**广告版（Special Offers）**。广告版拿不到 `wakeup_mgr`，定时刷新会静默失效，
  只剩"入睡瞬间定格"。这种情况要提前告知，让用户在"就这样用"和"先去掉广告"之间选。

### 第 1 轮：四个核心选择

用 AskUserQuestion 一次问完（最多 4 个问题）：

1. **时间刷新方式**
   - 对齐整点（推荐，走时最准，白天每小时闪一次）
   - 每 30 分钟（更实时，耗电和闪屏都更多）
   - 不刷新（零耗电，时间定格在入睡那一刻）
2. **天气**：三天 / 两天 / 一天 / 不要
3. **短句**：内置 80 句 / 自己写 / 不要
4. **内容详略**：全都要（含黄历宜忌）/ 精简（去黄历）/ 极简（只要时间+日期+周历）

### 第 2 轮：按结果补问

只问真正需要的：

- 选了天气 → 问**城市**（别问经纬度，用户不知道）。先查 `assets/city-coords.txt`（50 个常见城市已备好），
  查不到再用 Open-Meteo 地理编码转坐标：
  `https://geocoding-api.open-meteo.com/v1/search?name=<城市拼音>&count=1&language=zh`
  取 `latitude` / `longitude`，城市名留作日志用。中文名直接查常常无结果，用拼音（如 `jinjiang`、`quanzhou`）。
- 选了刷新 → 问**免打扰时段**（默认 7:00–23:00，夜里不唤醒也不闪屏）。
- 选了自定义短句 → 让用户直接贴，一行一句；少于 5 句提醒"轮换会很快重复"。
- 提到具体机型（PW2 / KPW3 / KPW5 / Oasis / KT3）→ 不需要额外参数，版式按屏幕高自动等比缩放，
  只在交付说明里告诉他缩放系数即可。

### 第 3 轮：复述确认

把最终参数用一张小表复述（刷新/时段/天气天数/城市/短句数量/显示区块），确认后再生成。
用户明确说"直接做"才可跳过。

## 生成

```bash
python scripts/build_patch.py --out <输出目录>/2-blbscreen.lua \
  --wake 0 \
  --wake-from 7 --wake-to 23 \
  --weather-days 3 --lat 24.78 --lon 118.55 --city 晋江 \
  --quotes builtin \
  --hide ""
```

| 参数 | 说明 |
|---|---|
| `--wake 0` | 0 = 对齐整点；30 = 每 30 分钟 |
| `--no-wake` | 完全关掉定时刷新（定格模式，零耗电） |
| `--weather-days 1..3` | 天气列数 |
| `--no-weather` | 不显示天气（自动不联网） |
| `--quotes builtin\|custom\|off` | 短句来源 |
| `--quotes-file <txt>` | 自定义句库，一行一句 |
| `--hide header,huangli` | 隐藏区块：header,clock,date,week,lunar,huangli,quote,footer |
| `--font-scale 1.1` | 整体字号，0.9–1.15 之间安全 |

脚本会把 `huangli.lua` 一起复制到输出目录，方便整体拷进设备。

生成后**必须做语法检查**。补丁语法错误会让 KOReader 启动时静默失败，用户只会看到"打不开了"：

```bash
luac -p 2-blbscreen.lua
# 没有 luac 时用 node：
npm i luaparse --no-save
node -e "require('luaparse').parse(require('fs').readFileSync(process.argv[1],'utf8'))" 2-blbscreen.lua
```

## 安装

完整步骤与排错见 `references/install.md`。核心四步：

1. `koreader/patches/` 放 `2-blbscreen.lua`
2. `koreader/plugins/blbscreen.koplugin/` 放 `huangli.lua` 和 `main.lua`（内容只有一行 `return { disabled = true }`）
3. Windows 托盘**安全弹出**后拔线（不弹直接拔是文件系统损坏的头号原因）
4. 退出 KOReader 再重进（patch 只在启动时加载），然后休眠看效果

验证刷新：设备根目录建空文件 `koreader/blbscreen.fastwake`，间隔变 180 秒；
`koreader/crash.log` 里应依次出现 `wakeup armed` / `RTC wake` / `next wake in ...`。

## 用户提额外需求时

用户常追加"能不能加个 X"。不要只答"能"或直接改代码，先把这四项问清，再给完整方案：

1. **数据从哪来**：本地固定 / 联网 API / 用户手动填
2. **多久更新一次**：跟随休眠重绘 / 每小时 / 每天
3. **放在版式哪个位置**：替换某个区块，还是新起一行；屏幕高度够不够
4. **拿不到数据时显示什么**：留空 / `--` / 隐藏该行

拿不准会不会撑破版式时，给两个方案让用户选（例如"挤掉黄历"或"缩小字号另起一行"），
不要默默做一个可能装不下的版本。

## 常见坑

- **不要替用户决定"要不要定时刷新"**：省电和走时是互斥的，必须让他选。
- **不要问经纬度**：问城市名，自己转坐标。
- **不要用 `luac` 之外还省略检查**：交付前必须 parse 一次。
- **不要改 `patches/` 里的文件名排序**：文件名前缀 `2-` 决定加载顺序，改了可能不生效。
- 唤醒重绘那一下会整屏闪一次，这是水墨屏全刷的物理特性，提前说明，别让用户以为是故障。

## 边界

- 黄历数据覆盖到 **2027-12-31**，超出后农历/宜忌显示 `--`，需要重新生成 `huangli.lua`。
- 天气依赖 Wi-Fi；无网时用上次缓存，连缓存都没有显示 `--`，不影响其他区块。
- 天气源是 Open-Meteo，海外可直连；网络受限时可能取不到，属正常降级。
