-- 这个目录只给 patches/2-blbscreen.lua 存数据（huangli.lua / weather.cache），
-- 本身不提供任何界面功能。
-- 用 disabled = true 让 PluginLoader 直接跳过实例化：
-- 旧版返回裸 table 没有 new 方法，启动时会报
-- "Failed to initialize blbscreen plugin: attempt to call a nil value"。
return { disabled = true }
