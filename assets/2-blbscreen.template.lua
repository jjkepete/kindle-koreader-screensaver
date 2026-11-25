--[[
Kindle / KOReader 休眠屏保  v5（可配置模板）
整屏 PNG 在设备端绘制：时间 + 周历 + 农历干支 + 黄历宜忌 + 天气 + 一句鸡汤
天气走 Open-Meteo（免 key），阅读时后台预热缓存，休眠只读缓存，唤醒窗口不联网

用法：把本文件放进 KOReader 的 patches/ 目录，命名为 2-blbscreen.lua。
配置集中在下面的 CFG 表；黄历数据放在 plugins/blbscreen.koplugin/huangli.lua。

设计基准：高 1024px 的屏幕（Kindle PW2 758x1024）。其它分辨率按高度等比缩放，
所以 PW3 / KPW5 / Oasis / KT3 都能直接用，不需要改坐标。
]]

-- @@CFG_BEGIN@@
local CFG = {
    -- ---------- 休眠定时刷新（时间/日期不再定格） ----------
    -- 关掉就退回"入睡瞬间定格"，零耗电
    wake_enabled   = true,
    -- 刷新间隔（分钟）：0 = 对齐整点（推荐，走时最准）；30 = 每半小时
    wake_interval_min = 0,
    -- 只在白天唤醒，夜间不闪屏。填 0 和 23 表示全天
    wake_hour_min  = 7,
    wake_hour_max  = 23,

    -- ---------- 天气 ----------
    weather_enabled = true,
    weather_lat     = "39.91",   -- 纬度：城市中心点，查 assets/city-coords.txt
    weather_lon     = "116.40",  -- 经度
    weather_days    = 3,         -- 显示几天：1 / 2 / 3
    weather_city    = "北京",     -- 仅用于日志，不显示在屏上

    -- ---------- 鸡汤 ----------
    -- builtin = 内置句库；custom = 读 plugin 目录下的 quotes.txt；off = 不显示
    quote_source      = "builtin",
    quote_custom_file = "",      -- 留空则用 plugins/blbscreen.koplugin/quotes.txt

    -- ---------- 区块开关（关掉后下面的内容自动上移） ----------
    show_header  = true,   -- 页眉：干支 + 年内第几天
    show_clock   = true,   -- 大号时:分
    show_date    = true,   -- 公历年月日 + 星期
    show_week    = true,   -- 本周七天，今天高亮
    show_lunar   = true,   -- 农历 + 干支 + 生肖
    show_huangli = true,   -- 宜 / 忌
    show_quote   = true,   -- 鸡汤
    show_footer  = true,   -- 底部"按电源键唤醒"

    -- ---------- 排版 ----------
    font_scale = 1.0,      -- 整体字号倍率，0.9 ~ 1.15 之间比较安全
}
-- @@CFG_END@@

local Device     = require("device")
local Screensaver= require("ui/screensaver")
local UIManager  = require("ui/uimanager")
local Screen     = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local RenderText = require("ui/rendertext")
local Font       = require("ui/font")
local logger     = require("logger")
local lfs        = require("libs/libkoreader-lfs")

local PLUGIN_DIR = "/mnt/us/koreader/plugins/blbscreen.koplugin"
local IMG_PATH   = "/mnt/us/koreader/blbscreen.png"
local HL_PATH    = PLUGIN_DIR .. "/huangli.lua"
local CACHE_PATH = PLUGIN_DIR .. "/weather.cache"
local LOG        = "blbscreen:"

local WAKE_ENABLED  = CFG.wake_enabled
local WAKE_HOUR_MIN = CFG.wake_hour_min
local WAKE_HOUR_MAX = CFG.wake_hour_max
local WAKE_INTERVAL = math.max(0, tonumber(CFG.wake_interval_min) or 0)

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local LINE  = Blitbuffer.COLOR_GRAY   -- 只用于分隔线，文字一律纯黑

-- ==================== 句库 ====================
-- 生成脚本会把句子填进下面两个标记之间
-- @@QUOTES_BEGIN@@
local QUOTES = {}
-- @@QUOTES_END@@

-- ==================== 工具 ====================
local function log(...)
    logger.info(LOG, ...)
end

-- UTF-8 字符迭代器：状态存在闭包里，避开泛型 for 控制变量回传的坑
local function utf8chars(s)
    local i, n = 1, #s
    return function()
        if i > n then return nil end
        local c = s:byte(i)
        local step = 1
        if c >= 0xF0 then step = 4
        elseif c >= 0xE0 then step = 3
        elseif c >= 0xC0 then step = 2 end
        local ch = s:sub(i, i + step - 1)
        i = i + step
        return ch
    end
end

local function usub(s, maxchars)
    if not s then return "" end
    local out, n = {}, 0
    for ch in utf8chars(s) do
        n = n + 1
        if n > maxchars then break end
        out[n] = ch
    end
    return table.concat(out)
end

local function charCount(s)
    local n = 0
    for _ in utf8chars(s) do n = n + 1 end
    return n
end

-- ==================== 字体与缩放 ====================
-- 设计基准高 1024；实际屏幕按高度等比缩放，字号同步缩放
local VSCALE = 1

local CJK_FACE = "NotoSansCJKsc-Regular.otf"
local function getFace(size)
    local real = math.max(9, math.floor(size * VSCALE * CFG.font_scale + 0.5))
    local f = Font:getFace(CJK_FACE, real)
    if not f then f = Font:getFace("cfont", real) end
    return f
end

local function textWidth(face, s)
    local ok, r = pcall(RenderText.sizeUtf8Text, RenderText, 0, 10000, face, s)
    if ok and r and r.x then return r.x end
    return 0
end

local function drawText(bb, x, baseline, face, text, color)
    if not text or text == "" then return 0 end
    local ok = pcall(RenderText.renderUtf8Text, RenderText, bb, x, baseline, face, text, nil, false, color or BLACK)
    if not ok then
        pcall(RenderText.renderUtf8Text, RenderText, bb, x, baseline, face, text, nil, false)
    end
    return textWidth(face, text)
end

local function drawCenter(bb, baseline, face, text, color)
    local w = textWidth(face, text)
    return drawText(bb, math.floor((bb:getWidth() - w) / 2), baseline, face, text, color)
end

local function drawCenterAt(bb, cx, baseline, face, text, color)
    local w = textWidth(face, text)
    return drawText(bb, math.floor(cx - w / 2), baseline, face, text, color)
end

local function drawRight(bb, xr, baseline, face, text, color)
    local w = textWidth(face, text)
    return drawText(bb, math.floor(xr - w), baseline, face, text, color)
end

local function fillRect(bb, x, y, w, h, color)
    x, y = math.floor(x), math.floor(y)
    w, h = math.floor(w), math.floor(h)
    if x < 0 then w = w + x; x = 0 end
    if y < 0 then h = h + y; y = 0 end
    if x + w > bb:getWidth() then w = bb:getWidth() - x end
    if y + h > bb:getHeight() then h = bb:getHeight() - y end
    if w <= 0 or h <= 0 then return end
    local ok = pcall(bb.paintRect, bb, x, y, w, h, color)
    if not ok then
        for yy = y, y + h - 1 do
            for xx = x, x + w - 1 do bb:setPixel(xx, yy, color) end
        end
    end
end

local function hline(bb, x1, x2, y, thick)
    fillRect(bb, x1, y, x2 - x1 + 1, thick or 1, LINE)
end

-- 空心边框
local function drawFrame(bb, x, y, w, h, thick, color)
    thick = thick or 1
    color = color or BLACK
    fillRect(bb, x, y, w, thick, color)
    fillRect(bb, x, y + h - thick, w, thick, color)
    fillRect(bb, x, y, thick, h, color)
    fillRect(bb, x + w - thick, y, thick, h, color)
end

local function wrapText(text, face, maxw)
    local lines, cur = {}, ""
    for ch in utf8chars(text) do
        local test = cur .. ch
        if cur ~= "" and textWidth(face, test) > maxw then
            lines[#lines + 1] = cur
            cur = ch
        else
            cur = test
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

-- ==================== 天气 ====================
local W_LAT, W_LON = CFG.weather_lat, CFG.weather_lon
local W_DAYS = math.max(1, math.min(3, tonumber(CFG.weather_days) or 3))

local function weatherUrl(scheme)
    return scheme .. "://api.open-meteo.com/v1/forecast?latitude=" .. W_LAT
        .. "&longitude=" .. W_LON
        .. "&current=temperature_2m,weather_code"
        .. "&daily=weather_code,temperature_2m_max,temperature_2m_min"
        .. "&timezone=Asia%2FShanghai&forecast_days=" .. tostring(W_DAYS)
end
local WEATHER_URLS = { weatherUrl("http"), weatherUrl("https") }

local WMO = {
    [0]="晴", [1]="多云", [2]="多云", [3]="阴", [45]="有雾", [48]="雾凇",
    [51]="小雨", [53]="小雨", [55]="中雨", [56]="冻雨", [57]="冻雨",
    [61]="小雨", [63]="中雨", [65]="大雨", [66]="冻雨", [67]="冻雨",
    [71]="小雪", [73]="中雪", [75]="大雪", [77]="米雪",
    [80]="阵雨", [81]="阵雨", [82]="暴雨", [85]="阵雪", [86]="阵雪",
    [95]="雷阵雨", [96]="雷阵雨", [99]="雷暴",
}

local function roundInt(v)
    v = tonumber(v)
    if not v then return nil end
    return math.floor(v + 0.5)
end

local function httpGet(url, timeout)
    local chunks = {}
    local ok3, socketutil = pcall(require, "socketutil")
    local okl, ltn12 = pcall(require, "ltn12")
    if not okl then return nil end

    if url:sub(1, 5) == "https" then
        local okh, https = pcall(require, "ssl.https")
        if not okh then return nil end
        if ok3 then socketutil:set_timeout(3, timeout or 6) end
        local okr, res, code = pcall(https.request, {
            url = url, sink = ltn12.sink.table(chunks), redirect = true,
        })
        if ok3 then pcall(socketutil.reset_timeout, socketutil) end
        if okr and (res == 1 or res == true) and (code == 200 or code == nil) then
            return table.concat(chunks)
        end
        return nil
    end

    local ok2, http = pcall(require, "socket.http")
    if not ok2 then return nil end
    if ok3 then socketutil:set_timeout(3, timeout or 6) end
    -- LuaSocket 3.x 返回 res, code, headers, status（不是老的 code, body）
    local okr, res, code = pcall(http.request, {
        url = url, sink = ltn12.sink.table(chunks), redirect = true,
    })
    if ok3 then pcall(socketutil.reset_timeout, socketutil) end
    if okr and (res == 1 or res == true) and (code == 200 or code == nil) then
        return table.concat(chunks)
    end
    log("http fail:", tostring(res), tostring(code))
    return nil
end

-- 缓存格式： "22,多云,18,26|20,晴,15,25|18,小雨,14,22|1763600000"
local function readCache()
    local f = io.open(CACHE_PATH, "r")
    if not f then return nil end
    local s = f:read("*l") or ""
    f:close()
    local parts = {}
    for seg in s:gmatch("[^|]+") do parts[#parts + 1] = seg end
    if #parts < 2 then return nil end
    local ts = tonumber(parts[#parts])
    if not ts then return nil end
    local days = {}
    for i = 1, #parts - 1 do
        local t, d, hi, lo = parts[i]:match("^(%-?%d+),([^,]*),([^,]*),([^,]*)$")
        if t then
            days[#days + 1] = { temp = tonumber(t), desc = d, hi = hi, lo = lo }
        end
    end
    if #days == 0 then return nil end
    return { days = days, ts = ts }
end

local function writeCache(w)
    local segs = {}
    for _, d in ipairs(w.days) do
        segs[#segs + 1] = string.format("%d,%s,%s,%s", d.temp, d.desc, d.hi or "", d.lo or "")
    end
    segs[#segs + 1] = tostring(os.time())
    local f = io.open(CACHE_PATH, "w")
    if f then f:write(table.concat(segs, "|")); f:close() end
end

local function fetchWeather(force)
    local cached = readCache()
    if cached and not force and (os.time() - cached.ts) < 1800 then
        return cached
    end
    for _, url in ipairs(WEATHER_URLS) do
        local body = httpGet(url)
        if body then
            local okj, json = pcall(require, "json")
            if okj then
                local okd, data = pcall(json.decode, body)
                if okd and data and data.current and data.daily then
                    local daily = data.daily
                    local hi_arr = daily.temperature_2m_max or {}
                    local lo_arr = daily.temperature_2m_min or {}
                    local wc_arr = daily.weather_code or {}
                    local days = {}
                    for i = 1, W_DAYS do
                        local hi = roundInt(hi_arr[i])
                        local lo = roundInt(lo_arr[i])
                        if hi then
                            local desc = WMO[tonumber(wc_arr[i]) or -1] or "多云"
                            local cur = (i == 1) and roundInt(data.current.temperature_2m) or nil
                            days[#days + 1] = {
                                temp = cur or hi,
                                desc = desc,
                                hi = tostring(hi),
                                lo = lo and tostring(lo) or "",
                            }
                        end
                    end
                    if #days > 0 then
                        local w = { days = days, ts = os.time() }
                        writeCache(w)
                        log("weather ok:", days[1].temp, days[1].desc, tostring(#days) .. "天")
                        return w
                    end
                end
            end
        end
    end
    return cached
end

-- ==================== 黄历 ====================
local HL_CACHE
local function getHuangli(t)
    if not HL_CACHE then
        local ok, data = pcall(dofile, HL_PATH)
        if ok and type(data) == "table" then
            local n = 0
            for _ in pairs(data) do n = n + 1 end
            HL_CACHE = data
            log("huangli loaded:", n)
        else
            log("huangli load fail:", tostring(data))
            HL_CACHE = false
        end
    end
    if not HL_CACHE then return nil end
    return HL_CACHE[string.format("%04d%02d%02d", t.year, t.month, t.day)]
end

local function tidyList(s, maxchars)
    if not s or s == "" then return "" end
    s = s:gsub(",", "、"):gsub("，", "、")
    if maxchars and charCount(s) > maxchars then
        s = usub(s, maxchars - 1) .. "…"
    end
    return s
end

-- ==================== 绘制 ====================
local function paint()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local W, H = math.min(sw, sh), math.max(sw, sh)

    -- 以 1024 高为设计基准等比缩放（PW2 758x1024 → 1.00，PW3 1072x1448 → 1.41）
    VSCALE = H / 1024
    local S = VSCALE

    local function Y(v) return math.floor(v * S + 0.5) end
    local function Z(v) return math.max(1, math.floor(v * S + 0.5)) end

    local bb = Blitbuffer.new(W, H, Blitbuffer.TYPE_BB8)
    if not bb then
        log("cannot create buffer")
        return false
    end
    bb:fill(WHITE)

    local t  = os.date("*t")
    local hl = getHuangli(t) or {}

    local f_time  = getFace(96)
    local f_date  = getFace(22)
    local f_wlbl  = getFace(16)
    local f_wnum  = getFace(26)
    local f_lunar = getFace(34)
    local f_label = getFace(19)
    local f_gz    = getFace(19)
    local f_small = getFace(17)
    local f_chip  = getFace(19)
    local f_body  = getFace(20)
    local f_wtemp = getFace(28)
    local f_quote = getFace(19)
    local f_tiny  = getFace(14)

    local M  = Z(52)
    local xr = W - M

    -- 关掉某个区块时，后面的内容整体上移
    local off = 0

    -- ---------- 页眉 ----------
    if CFG.show_header then
        hline(bb, M, xr, Y(60), Z(1))
        local gz_short = hl.gz and hl.gz:match("^(%S+)") or ""
        drawText(bb, M, Y(96), f_small, gz_short, BLACK)
        drawRight(bb, xr, Y(96), f_small, string.format("第 %d 天", t.yday or 0), BLACK)
    else
        off = off + Z(46)
    end

    -- ---------- 时间 ----------
    if CFG.show_clock then
        local hh = string.format("%02d", t.hour)
        local mm = string.format("%02d", t.min)
        local wh, wc, wm = textWidth(f_time, hh), textWidth(f_time, ":"), textWidth(f_time, mm)
        local tx = math.floor((W - (wh + wc + wm)) / 2)
        drawText(bb, tx, Y(230), f_time, hh, BLACK)
        drawText(bb, tx + wh, Y(230), f_time, ":", BLACK)
        drawText(bb, tx + wh + wc, Y(230), f_time, mm, BLACK)
    else
        off = off + Z(134)
    end

    -- ---------- 公历日期 ----------
    if CFG.show_date then
        local datestr = string.format("%d年%d月%d日   星期%s", t.year, t.month, t.day, hl.w or "")
        drawCenter(bb, Y(300) - off, f_date, datestr, BLACK)
    else
        off = off + Z(70)
    end

    -- ---------- 周历 ----------
    if CFG.show_week then
        local WK_LBL = { "日", "一", "二", "三", "四", "五", "六" }
        local dow = t.wday or 1
        local base = os.time{ year = t.year, month = t.month, day = t.day, hour = 12, min = 0, sec = 0 }
        local colw = (xr - M) / 7

        for i = 1, 7 do
            drawCenterAt(bb, M + colw * (i - 0.5), Y(366) - off, f_wlbl, WK_LBL[i], BLACK)
        end
        for i = 1, 7 do
            local dayt = os.date("*t", base + (i - dow) * 86400)
            local cx = M + colw * (i - 0.5)
            local s = tostring(dayt.day)
            if i == dow then
                -- 今天：黑底白字方块 + 外圈细边框
                local bw, bh = Z(54), Z(44)
                local bx, by = math.floor(cx - bw / 2), Y(386) - off
                fillRect(bb, bx, by, bw, bh, BLACK)
                drawCenterAt(bb, cx, Y(421) - off, f_wnum, s, WHITE)
                drawFrame(bb, bx - Z(9), by - Z(9), bw + Z(18), bh + Z(18), Z(2), BLACK)
            else
                drawCenterAt(bb, cx, Y(421) - off, f_wnum, s, BLACK)
            end
        end
        hline(bb, M, xr, Y(460) - off, Z(1))
    else
        off = off + Z(106)
    end

    -- ---------- 农历 + 干支 ----------
    if CFG.show_lunar then
        local label_w = textWidth(f_label, "农历")
        drawText(bb, M, Y(508) - off, f_label, "农历", BLACK)
        drawText(bb, M + label_w + Z(14), Y(518) - off, f_lunar, hl.lm or "--", BLACK)

        local gzline = hl.gz or ""
        if hl.ch and hl.ch ~= "" then
            gzline = gzline .. (gzline ~= "" and "   " or "") .. hl.ch
        end
        drawText(bb, M, Y(560) - off, f_gz, gzline, BLACK)
    else
        off = off + Z(52)
    end

    -- ---------- 宜忌 ----------
    if CFG.show_huangli then
        local chip_w, chip_h = Z(46), Z(30)
        local body_x = M + chip_w + Z(22)

        local function drawChip(ytop, txt, bg, fg, bordered)
            fillRect(bb, M, ytop, chip_w, chip_h, bg)
            if bordered then drawFrame(bb, M, ytop, chip_w, chip_h, Z(2), BLACK) end
            drawCenterAt(bb, M + chip_w / 2, ytop + chip_h - Z(9), f_chip, txt, fg)
        end

        local yi_top = Y(604) - off
        drawChip(yi_top, "宜", BLACK, WHITE, false)
        drawText(bb, body_x, yi_top + Z(22), f_body, tidyList(hl.yi or "诸事不宜", 24), BLACK)

        local ji_top = yi_top + Z(46)
        drawChip(ji_top, "忌", WHITE, BLACK, true)
        drawText(bb, body_x, ji_top + Z(22), f_body, tidyList(hl.ji or "诸事不忌", 24), BLACK)
    else
        off = off + Z(144)
    end

    -- ---------- 天气 ----------
    if CFG.weather_enabled then
        local w = readCache()
        -- 休眠/屏保状态下绝不联网：唤醒窗口只用来重绘，天气用阅读时预热的缓存
        if not w and not Device.screen_saver_mode then w = fetchWeather(true) end
        local wlabel_w = textWidth(f_label, "天气")
        drawText(bb, M, Y(748) - off, f_label, "天气", BLACK)

        local WD_LBL = { "今天", "明天", "后天" }
        local wx0 = M + wlabel_w + Z(24)
        local wcolw = (xr - wx0) / W_DAYS

        for i = 1, W_DAYS do
            local cx = wx0 + wcolw * (i - 0.5)
            local d = w and w.days and w.days[i]
            drawCenterAt(bb, cx, Y(748) - off, f_small, WD_LBL[i], BLACK)
            if d then
                drawCenterAt(bb, cx, Y(790) - off, f_wtemp, tostring(d.temp) .. "°", BLACK)
                drawCenterAt(bb, cx, Y(818) - off, f_small, d.desc or "", BLACK)
            else
                drawCenterAt(bb, cx, Y(790) - off, f_wtemp, "--", BLACK)
            end
        end
    else
        off = off + Z(118)
    end

    -- ---------- 鸡汤 ----------
    if CFG.show_quote and CFG.quote_source ~= "off" and #QUOTES > 0 then
        local qidx = ((t.year * 372 + (t.yday or 1)) % #QUOTES) + 1
        local quote = "「" .. QUOTES[qidx] .. "」"
        local qlines = wrapText(quote, f_quote, xr - M)
        if #qlines > 2 then
            qlines = { qlines[1], usub(qlines[2], math.max(1, charCount(qlines[2]) - 1)) .. "…" }
        end
        local qbase = (#qlines >= 2) and (Y(908) - off) or (Y(924) - off)
        for i, ln in ipairs(qlines) do
            drawCenter(bb, qbase + (i - 1) * Z(30), f_quote, ln, BLACK)
        end
    end

    -- ---------- 页脚 ----------
    if CFG.show_footer then
        drawCenter(bb, Y(992), f_tiny, "按电源键唤醒", BLACK)
    end

    local ok, err = pcall(function() bb:writePNG(IMG_PATH) end)
    if not ok then
        log("writePNG fail:", tostring(err))
        return false
    end
    local wtxt = "no-weather"
    local w2 = readCache()
    if w2 and w2.days and w2.days[1] then wtxt = tostring(w2.days[1].temp) .. "度" end
    log("painted", string.format("%02d:%02d", t.hour, t.min), hl.lm or "", wtxt)
    return true
end

-- ==================== 自定义句库 ====================
local function loadQuotes()
    if CFG.quote_source ~= "custom" then return end
    local p = CFG.quote_custom_file
    if not p or p == "" then p = PLUGIN_DIR .. "/quotes.txt" end
    local f = io.open(p, "r")
    if not f then
        log("custom quotes missing:", p, "- fallback to builtin")
        return
    end
    local list = {}
    for line in f:lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then list[#list + 1] = line end
    end
    f:close()
    if #list > 0 then
        QUOTES = list
        log("custom quotes loaded:", #list)
    end
end

-- ==================== 后台预热 ====================
local function startWeatherPrewarm()
    if not CFG.weather_enabled then return end
    if _G.__blb_prewarm_started then return end
    _G.__blb_prewarm_started = true
    local function loop()
        -- 屏保/休眠期间不联网预热，免得 RTC 唤醒窗口被网络拖长
        if not Device.screen_saver_mode then
            pcall(fetchWeather, true)
        end
        pcall(UIManager.scheduleIn, UIManager, 1800, loop)
    end
    pcall(UIManager.scheduleIn, UIManager, 60, loop)
    log("prewarm scheduled")
end

-- ==================== 定时唤醒（RTC） ====================
-- Kindle 非广告版：KOReader 挂起前通过 lipc 的 com.lab126.powerd.rtcWakeup 布闹钟，
-- 到点唤醒 CPU 跑回调（约 wakeup+15s），重绘完 powerd 自动回睡。
-- 广告版（SO）拿不到 wakeup_mgr，这里会自动跳过，退回“入睡瞬间定格”。
local WAKE_CB

-- 测试开关：设备上建一个空文件 koreader/blbscreen.fastwake，
-- 唤醒间隔改成 180 秒，方便当场验证；验证完删掉即可恢复整点唤醒
local FASTWAKE_FILE = "/mnt/us/koreader/blbscreen.fastwake"

local function nextWakeSeconds()
    if lfs.attributes(FASTWAKE_FILE, "mode") == "file" then
        return 180
    end
    local now = os.time()
    local t   = os.date("*t", now)

    -- 按固定间隔刷新（30 / 60 分钟等）
    if WAKE_INTERVAL > 0 then
        local target = now + WAKE_INTERVAL * 60
        local tt = os.date("*t", target)
        if tt.hour < WAKE_HOUR_MIN or tt.hour > WAKE_HOUR_MAX then
            target = os.time{ year = tt.year, month = tt.month, day = tt.day,
                              hour = WAKE_HOUR_MIN, min = 0, sec = 0 }
        end
        local secs = target - now
        if secs < 60 then secs = 60 end
        return secs
    end

    -- 对齐到下一个整点（走时最准）
    local target = os.time{ year = t.year, month = t.month, day = t.day,
                            hour = t.hour + 1, min = 0, sec = 0 }
    -- powerd 要在挂起序列里提交，闹钟必须比“现在”晚足够久
    if target - now < 120 then target = target + 3600 end
    local tt = os.date("*t", target)
    if tt.hour < WAKE_HOUR_MIN or tt.hour > WAKE_HOUR_MAX then
        local day = tt.day
        if tt.hour > WAKE_HOUR_MAX then day = day + 1 end
        target = os.time{ year = tt.year, month = tt.month, day = day,
                          hour = WAKE_HOUR_MIN, min = 0, sec = 0 }
    end
    local secs = target - now
    if secs < 60 then secs = 60 end
    return secs
end

-- 只布新闹钟，不动队列：在 wakeupAction 回调里调用时，
-- 框架紧接着会 removeTask(1) 弹掉已触发的那个，提前 removeTasks 会把新任务一起删掉。
local function armNext()
    if not WAKE_ENABLED then return end
    if not Device.wakeup_mgr then return end
    pcall(function()
        local secs = nextWakeSeconds()
        Device.wakeup_mgr:addTask(secs, WAKE_CB)
        log("next wake in", secs, "s")
    end)
end

local function scheduleWakeup()
    if not WAKE_ENABLED then return end
    if not Device.wakeup_mgr then
        log("no wakeup_mgr (SO device?), scheduled refresh disabled")
        return
    end
    pcall(function()
        Device.wakeup_mgr:removeTasks(nil, WAKE_CB)
        Device.wakeup_mgr:addTask(nextWakeSeconds(), WAKE_CB)
        log("wakeup armed")
    end)
end

local function cancelWakeup()
    if not Device.wakeup_mgr then return end
    pcall(function()
        Device.wakeup_mgr:removeTasks(nil, WAKE_CB)
        Device.wakeup_mgr:unsetWakeupAlarm()
        log("wakeup cancelled")
    end)
end

-- 屏保已经在屏幕上，重绘后要让 ImageWidget 丢掉旧位图重新读 PNG
local function refreshScreen()
    local ss = require("ui/screensaver")
    local sw = ss.screensaver_widget
    if not sw then return false end
    local frame = sw[1]
    local iw    = frame and frame[1]
    if iw and iw.free then
        pcall(iw.free, iw)          -- 清掉 _bb，强制 _render 重新读文件
        iw.file          = IMG_PATH
        iw.image         = nil
        iw.file_do_cache = false
    end
    UIManager:setDirty("all", "full")
    UIManager:forceRePaint()
    return true
end

WAKE_CB = function()
    log("RTC wake")
    local ok, err = pcall(paint)
    if not ok then log("wake repaint error:", tostring(err)) end
    pcall(refreshScreen)
    armNext()
end

-- ==================== Hook ====================
local orig_setup = Screensaver.setup
if orig_setup then
    Screensaver.setup = function(self, event, event_message)
        local ok = pcall(paint)
        log("setup hook, painted:", tostring(ok))
        orig_setup(self, event, event_message)
        if ok and lfs.attributes(IMG_PATH, "mode") == "file" then
            self.screensaver_type = "cover"
            self.image = nil
            self.image_file = IMG_PATH
            self.show_message = false
            self.overlay_message = nil
            self.screensaver_background = G_reader_settings:readSetting("screensaver_img_background") or "white"
            log("hooked to our image")
            -- 正常休眠才布闹钟；关机/重启（带 event）不布
            if not event then scheduleWakeup() end
        end
    end
else
    log("Screensaver.setup not found")
end

-- 用户唤醒时立刻撤掉闹钟，免得看书看到一半被定时唤醒来一下
local orig_close = Screensaver.close
if orig_close then
    Screensaver.close = function(self, ...)
        cancelWakeup()
        return orig_close(self, ...)
    end
end

loadQuotes()

if lfs.attributes(IMG_PATH, "mode") ~= "file" then
    UIManager:scheduleIn(2, function() pcall(paint) end)
end

startWeatherPrewarm()

log("plugin loaded v5")
