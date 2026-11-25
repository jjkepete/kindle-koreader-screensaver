#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成"免 AI 直装包"：一个解压到 Kindle 根目录就能用的文件夹。

目录结构：
    <out>/koreader/patches/2-blbscreen.lua
    <out>/koreader/plugins/blbscreen.koplugin/main.lua
    <out>/koreader/plugins/blbscreen.koplugin/huangli.lua
    <out>/安装说明.txt
    <out>/城市坐标表.txt

用法：
    python build_install_pack.py --out ./Kindle休眠屏保-直装包 --lat 39.91 --lon 116.40 --city 北京
"""

import argparse
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL_DIR = os.path.dirname(HERE)
ASSETS = os.path.join(SKILL_DIR, "assets")

README = """Kindle 休眠屏保 · 直装包
================================

不用装任何软件，把这个文件夹里的内容原样拷到 Kindle 根目录就行。

一、先确认
  1. Kindle 已经越狱，并且装好了 KOReader。
  2. 你的 Kindle 不是广告版（锁屏出现亚马逊促销广告图的那种就是广告版）。
     广告版做不出"时间自动走"，只能定格在入睡那一刻。

二、拷贝
  1. USB 线连电脑，等 Kindle 出现在"此电脑"里。
  2. 把本文件夹里的 koreader 文件夹，整个拖到 Kindle 根目录
     （就是能看到 documents、system 这些文件夹的那一层）。
  3. 弹出提示"是否合并文件夹"时选"是"；提示"是否替换文件"也选"是"。

三、改你所在的城市（重要）
  打开 koreader/patches/2-blbscreen.lua，用记事本即可，
  找到这两行：
      weather_lat     = "%.2f",
      weather_lon     = "%.2f",
  按《城市坐标表.txt》改成你所在城市的数字，保存。
  不改的话显示的是 %s 的天气。

四、生效
  1. Windows 右下角托盘 → 安全弹出 Kindle → 提示可以移除后再拔线。
     （千万别直接拔，容易把文件写坏）
  2. 打开 KOReader。如果它已经在运行，从菜单里退出，再重新进一次。
  3. 按电源键休眠，看屏保。

五、常用开关（都在 2-blbscreen.lua 顶部）
  wake_enabled   = true    改成 false：不做定时刷新，最省电，时间定格
  wake_hour_min  = 7       最早几点唤醒（夜里不闪屏）
  wake_hour_max  = 23      最晚几点唤醒
  weather_days   = 3       天气显示几天，可改 1 / 2 / 3
  quote_source   = "builtin"  短句：builtin 内置 80 句 / custom 用自备 / off 不显示
  show_huangli   = true    改成 false：不显示宜忌
  font_scale     = 1.0     整体字号，0.9 到 1.15 之间调

六、验证时间会不会自己走
  在 Kindle 根目录建一个空文件：koreader/blbscreen.fastwake
  建好后休眠，三分钟就会刷新一次。
  验证完把这个文件删掉，恢复每小时整点刷新。

七、出问题怎么办
  屏保没变化：补丁没加载。确认文件在 koreader/patches/ 里，名字是 2-blbscreen.lua，
              然后退出 KOReader 再进一次。
  时间不走：多半是广告版；也可能 wake_enabled 被改成了 false。
  天气是 --：Kindle 没连过网。先联网看会儿书，它会在后台缓存天气。
  黄历是 --：日期超出数据范围（2025-12 到 2027-12）。
  KOReader 打不开：把 patches/2-blbscreen.lua 改名加个 .bak，就能恢复。

  详细日志看 koreader/crash.log，搜 blbscreen。
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--lat", default="39.91")
    ap.add_argument("--lon", default="116.40")
    ap.add_argument("--city", default="北京")
    ap.add_argument("--weather-days", type=int, default=3, choices=[1, 2, 3])
    ap.add_argument("--wake", type=int, default=0)
    ap.add_argument("--quotes", default="builtin", choices=["builtin", "custom", "off"])
    args = ap.parse_args()

    out = os.path.abspath(args.out)
    patch_dir = os.path.join(out, "koreader", "patches")
    plug_dir = os.path.join(out, "koreader", "plugins", "blbscreen.koplugin")
    os.makedirs(patch_dir, exist_ok=True)
    os.makedirs(plug_dir, exist_ok=True)

    lua_out = os.path.join(patch_dir, "2-blbscreen.lua")
    cmd = [sys.executable, os.path.join(HERE, "build_patch.py"),
           "--out", lua_out,
           "--lat", str(args.lat), "--lon", str(args.lon), "--city", args.city,
           "--weather-days", str(args.weather_days), "--wake", str(args.wake),
           "--quotes", args.quotes]
    subprocess.check_call(cmd)

    # build_patch 会把 huangli.lua 复制到补丁同级，直装包里它应该只在插件目录
    stray = os.path.join(patch_dir, "huangli.lua")
    if os.path.isfile(stray):
        os.remove(stray)

    shutil.copy2(os.path.join(ASSETS, "plugin-main.lua"),
                 os.path.join(plug_dir, "main.lua"))
    shutil.copy2(os.path.join(ASSETS, "huangli.lua"),
                 os.path.join(plug_dir, "huangli.lua"))

    with open(os.path.join(out, "安装说明.txt"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(README % (float(args.lat), float(args.lon), args.city))

    coords = os.path.join(ASSETS, "city-coords.txt")
    if os.path.isfile(coords):
        shutil.copy2(coords, os.path.join(out, "城市坐标表.txt"))

    print("直装包 -> %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
