#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 2-blbscreen.template.lua + 用户选项，生成可直接放进 KOReader patches/ 的 2-blbscreen.lua。

只做「精确替换」：按行定位 CFG 里的键，替换值，注释与结构原样保留。
不重排代码，不生成新逻辑，改错的风险最低。

用法示例：
    python build_patch.py --out ./2-blbscreen.lua --wake 60 --wake-from 7 --wake-to 23 \
        --weather-days 3 --lat 24.78 --lon 118.55 --quotes builtin

    python build_patch.py --out ./2-blbscreen.lua --no-wake --no-weather --hide week,huangli
"""

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL_DIR = os.path.dirname(HERE)
TEMPLATE = os.path.join(SKILL_DIR, "assets", "2-blbscreen.template.lua")
DEFAULT_QUOTES = os.path.join(SKILL_DIR, "assets", "quotes-default.txt")
DEFAULT_HUANGLI = os.path.join(SKILL_DIR, "assets", "huangli.lua")

SHOW_KEYS = {
    "header": "show_header",
    "clock": "show_clock",
    "date": "show_date",
    "week": "show_week",
    "lunar": "show_lunar",
    "huangli": "show_huangli",
    "quote": "show_quote",
    "footer": "show_footer",
}


def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'


def set_key(text, key, value):
    """替换 CFG 里 `key = xxx,` 的值，保留缩进、逗号和行尾注释。"""
    pattern = re.compile(
        r"^(\s*" + re.escape(key) + r"\s*=\s*)([^,\n]+)(,?)(\s*--.*)?$",
        re.MULTILINE,
    )
    new, n = pattern.subn(lambda m: m.group(1) + lua_value(value) + m.group(3) + (m.group(4) or ""), text, count=1)
    if n != 1:
        raise SystemExit("ERROR: 找不到配置项 %r，模板可能被改动过" % key)
    return new


def load_quotes(path):
    with open(path, "r", encoding="utf-8") as f:
        lines = [ln.strip() for ln in f if ln.strip() and not ln.strip().startswith("#")]
    return lines


def quotes_block(quotes):
    body = "local QUOTES = {\n"
    for q in quotes:
        body += '    "%s",\n' % q.replace("\\", "\\\\").replace('"', '\\"')
    body += "}"
    return body


def replace_marked(text, begin, end, content):
    pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.S)
    new, n = pattern.subn(lambda m: begin + "\n" + content + "\n" + end, text, count=1)
    if n != 1:
        raise SystemExit("ERROR: 找不到标记 %s / %s" % (begin, end))
    return new


def main():
    ap = argparse.ArgumentParser(description="生成 Kindle KOReader 屏保补丁")
    ap.add_argument("--out", required=True, help="输出的 2-blbscreen.lua 路径")
    ap.add_argument("--wake", type=int, default=0,
                    help="刷新间隔（分钟）：0=对齐整点（默认，走时最准）；30=每半小时")
    ap.add_argument("--no-wake", action="store_true", help="关闭休眠定时刷新（定格模式，零耗电）")
    ap.add_argument("--wake-from", type=int, default=7, help="最早唤醒整点 0-23")
    ap.add_argument("--wake-to", type=int, default=23, help="最晚唤醒整点 0-23")
    ap.add_argument("--weather-days", type=int, default=3, choices=[1, 2, 3], help="天气显示天数")
    ap.add_argument("--lat", default="24.78", help="纬度")
    ap.add_argument("--lon", default="118.55", help="经度")
    ap.add_argument("--city", default="晋江", help="城市名，仅日志用")
    ap.add_argument("--no-weather", action="store_true", help="不显示天气")
    ap.add_argument("--quotes", default="builtin", choices=["builtin", "custom", "off"],
                    help="鸡汤来源：内置 / 自定义 quotes.txt / 不显示")
    ap.add_argument("--quotes-file", default="", help="自定义句库 txt 路径（一行一句）")
    ap.add_argument("--font-scale", type=float, default=1.0, help="字号倍率 0.9-1.15")
    ap.add_argument("--hide", default="", help="隐藏区块，逗号分隔：header,clock,date,week,lunar,huangli,quote,footer")
    ap.add_argument("--show", default="", help="额外显示的区块（与 --hide 二选一即可）")
    ap.add_argument("--json", default="", help="用 JSON 文件一次性传入全部选项（键名同上划线形式）")
    args = ap.parse_args()

    opts = {}
    if args.json:
        with open(args.json, "r", encoding="utf-8") as f:
            opts = json.load(f)
        args.wake = opts.get("wake", args.wake)
        args.wake_from = opts.get("wake_from", args.wake_from)
        args.wake_to = opts.get("wake_to", args.wake_to)
        args.weather_days = opts.get("weather_days", args.weather_days)
        args.lat = opts.get("lat", args.lat)
        args.lon = opts.get("lon", args.lon)
        args.city = opts.get("city", args.city)
        args.quotes = opts.get("quotes", args.quotes)
        args.quotes_file = opts.get("quotes_file", args.quotes_file)
        args.font_scale = opts.get("font_scale", args.font_scale)
        args.hide = ",".join(opts.get("hide", [])) if isinstance(opts.get("hide"), list) else opts.get("hide", args.hide)
        args.no_wake = opts.get("no_wake", args.no_wake)
        args.no_weather = opts.get("no_weather", args.no_weather)

    with open(TEMPLATE, "r", encoding="utf-8") as f:
        text = f.read()

    # 唤醒：0 = 整点对齐，>0 = 固定间隔分钟
    text = set_key(text, "wake_enabled", not args.no_wake)
    text = set_key(text, "wake_interval_min", max(0, args.wake))
    text = set_key(text, "wake_hour_min", max(0, min(23, args.wake_from)))
    text = set_key(text, "wake_hour_max", max(0, min(23, args.wake_to)))

    text = set_key(text, "weather_enabled", not args.no_weather)
    text = set_key(text, "weather_lat", args.lat)
    text = set_key(text, "weather_lon", args.lon)
    text = set_key(text, "weather_days", args.weather_days)
    text = set_key(text, "weather_city", args.city)
    text = set_key(text, "quote_source", args.quotes)
    text = set_key(text, "quote_custom_file", args.quotes_file or "")
    text = set_key(text, "font_scale", args.font_scale)

    hide = {h.strip() for h in args.hide.split(",") if h.strip()}
    unknown = hide - set(SHOW_KEYS)
    if unknown:
        raise SystemExit("ERROR: --hide 里有不认识的区块：%s" % ", ".join(sorted(unknown)))
    for short, key in SHOW_KEYS.items():
        text = set_key(text, key, short not in hide)

    # 句库：custom 时仍内置一份作兜底
    qpath = args.quotes_file if (args.quotes == "custom" and args.quotes_file) else DEFAULT_QUOTES
    if not os.path.isfile(qpath):
        qpath = DEFAULT_QUOTES
    quotes = load_quotes(qpath)
    if not quotes:
        raise SystemExit("ERROR: 句库为空：%s" % qpath)
    text = replace_marked(text, "-- @@QUOTES_BEGIN@@", "-- @@QUOTES_END@@", quotes_block(quotes))

    if "local QUOTES = {\n}" in text:
        raise SystemExit("ERROR: 句库没写进去")

    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

    # 同时把黄历数据放到 out 同级，方便一起拷进设备
    out_dir = os.path.dirname(out)
    if os.path.isfile(DEFAULT_HUANGLI):
        dst = os.path.join(out_dir, "huangli.lua")
        if os.path.abspath(dst) != os.path.abspath(DEFAULT_HUANGLI):
            with open(DEFAULT_HUANGLI, "rb") as src, open(dst, "wb") as d:
                d.write(src.read())

    print("OK -> %s" % out)
    print("   区块: %s" % (", ".join(sorted(set(SHOW_KEYS) - hide)) or "(全关)"))
    print("   唤醒: %s %s %02d:00-%02d:00" % (
        "关" if args.no_wake else "开",
        "整点" if args.wake == 0 else ("每%d分钟" % args.wake),
        args.wake_from, args.wake_to))
    print("   天气: %s %d天 (%.2f, %.2f)" % ("关" if args.no_weather else "开", args.weather_days,
                                        float(args.lat), float(args.lon)))
    print("   鸡汤: %s（%d 句）" % (args.quotes, len(quotes)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
