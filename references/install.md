# 安装与排错

## 一、装之前先确认

| 前提 | 不满足会怎样 |
|---|---|
| Kindle 已越狱 | 无法运行 KOReader，本补丁无用 |
| 已装 KOReader（v2020.03 以上） | 老版本没有 `Screensaver.setup` 钩子，补丁不生效 |
| 非广告版（Special Offers） | 拿不到 `wakeup_mgr`，定时刷新静默失效，只剩入睡定格 |
| 用 USB 数据线连电脑能出现盘符 | 不能传文件，一切免谈 |

广告版辨认：锁屏时有亚马逊促销广告图的，就是广告版。

## 二、文件放哪

```
Kindle 根目录/
└── koreader/
    ├── patches/
    │   └── 2-blbscreen.lua          ← 主补丁
    ├── plugins/
    │   └── blbscreen.koplugin/
    │       ├── main.lua             ← 一行：return { disabled = true }
    │       ├── huangli.lua          ← 黄历数据（约 145 KB）
    │       └── quotes.txt           ← 仅"自定义短句"时才有
    └── settings.reader.lua          ← 不用改，补丁会自己接管
```

要点：

- `patches/` 里的文件名前缀 `2-` 决定加载时机（数字小的先加载，`2-` 属于较晚的钩子）。
  **不要改名**成 `zz-` 之外的其它前缀，否则可能在 `Screensaver` 初始化之前或之后跑，钩不上。
- `blbscreen.koplugin/main.lua` 只做一件事：让这个目录被 KOReader 识别为合法插件目录，
  但不参与插件实例化。内容必须是 `return { disabled = true }`。
  写成裸 `return {}` 会在启动日志里刷 `Failed to initialize ... attempt to call a nil value`。
- 目录名必须以 `.koplugin` 结尾，少一个字母就只是普通文件夹。

## 三、写入的正确姿势

Windows 上往 Kindle 写文件，出错基本都是这两件事：

1. **没安全弹出**。FAT32 分区有写缓存，直接拔线会让最后写入的文件变成半截，
   轻则补丁不加载，重则 Kindle 系统索引进程崩溃、弹 `Collecting Debug Info`。
   正确做法：任务栏托盘 → 弹出 → 等提示"可以安全移除" → 再拔线。
2. **同名文件已存在时直接覆盖失败**。Kindle 的 FAT32 有时会锁定已有文件。
   遇到 `拒绝访问` / 写入后大小为 0：先改名为 `xxx.bak`（或备份到电脑），删掉原文件，
   重开 USB 连接再写入新文件。

写入后建议核对一次字节数，别只看"没报错"。

## 四、生效步骤

1. 拔线（确保已安全弹出）
2. 打开 KOReader（如果已经在运行，从菜单里**退出**再重新进入——不是重启设备）
3. 按电源键休眠，看屏保

patch 只在 KOReader 启动时加载一次，所以第 2 步不能省。

## 五、日志对照

插线连电脑，看 `koreader/crash.log` 末尾：

| 日志 | 含义 |
|---|---|
| `blbscreen: plugin loaded v5` | 补丁加载成功 |
| `blbscreen: huangli loaded: 761` | 黄历读到 761 天，正常 |
| `blbscreen: painted 21:04 十月十七 18度` | 画图成功 |
| `blbscreen: setup hook, painted: true` | 休眠钩子生效 |
| `blbscreen: hooked to our image` | 屏保已替换成自己的图 |
| `blbscreen: weather ok: 22 多云 3天` | 天气抓到 |
| `blbscreen: http fail: ...` | 联网失败，用缓存，不影响 |
| `blbscreen: wakeup armed` | 入睡时闹钟已布好 |
| `blbscreen: RTC wake` | 闹钟确实唤醒了设备 |
| `blbscreen: next wake in 3600 s` | 下一轮闹钟已布好 |
| `blbscreen: no wakeup_mgr (SO device?)` | 广告版，定时刷新不可用 |

三行 `wakeup armed` → `RTC wake` → `next wake in` 都出现，说明链路完整。

## 六、快速验证刷新（不用等一小时）

在 Kindle 根目录建一个**空的**文件：

```
koreader/blbscreen.fastwake
```

建好后休眠，间隔变成 180 秒。三分钟后屏保时间应该自己跳一次（同时整屏闪一下）。
验证完删掉这个文件，恢复整点唤醒。

注意：文件名必须完全一致，内容必须为空。

## 七、常见故障

**屏保不出现，还是系统原图**
- 补丁没加载：确认文件名是 `2-blbscreen.lua`、路径是 `koreader/patches/`
- KOReader 没重启：退出再进一次
- `crash.log` 里搜 `blbscreen`，一行都没有 = 文件没放对位置

**屏保出现但时间是定格**
- 广告版设备（看日志 `no wakeup_mgr`）
- `CFG.wake_enabled = false`
- 免打扰时段设得太窄，比如 9:00–10:00，一天只唤醒一次

**中文变乱码/方块**
- 设备缺 `NotoSansCJKsc-Regular.otf` 字体。补丁会自动退回 `cfont`，但如果 `cfont` 也缺中文，
  就会显示方块。解决：把任意中文字体改名为 `NotoSansCJKsc-Regular.otf` 放进
  `koreader/fonts/` 目录。

**天气一直是 `--`**
- 设备没连 Wi-Fi，且从未成功抓过
- 先用 KOReader 联网看会儿书（联网时后台会预热缓存，每 30 分钟一次）
- 网络环境访问不了 `api.open-meteo.com`

**黄历显示 `--`**
- 日期超出 `huangli.lua` 覆盖范围（2025-12-01 ~ 2027-12-31）
- 文件没放进 `plugins/blbscreen.koplugin/`

**弹 `Collecting Debug Info` / `Generating Core Dump`**
- 这是 Kindle 系统进程（常见是 `scanner` 索引进程）崩了，不是 KOReader。
  多半由非正常拔线导致文件系统有脏数据。
- 处理：点"关闭"→ 长按电源 20 秒强制重启 → 重新进 KOReader。
- 反复出现：删掉 `system/Search Indexes/` 让系统重建索引（这个操作要谨慎，只删这一个目录）。

**KOReader 启动不了 / 一闪就退**
- 九成是补丁语法错误。用 `luac -p 2-blbscreen.lua` 查一遍。
- 应急：把 `patches/2-blbscreen.lua` 改名成 `2-blbscreen.lua.bak`，KOReader 立刻能启动。

## 八、卸载

删掉这两个即可，KOReader 原设置不受影响：

- `koreader/patches/2-blbscreen.lua`
- `koreader/plugins/blbscreen.koplugin/`（整个目录）

剩余 `koreader/blbscreen.png` 和 `blbscreen.fastwake` 可一并删除。
