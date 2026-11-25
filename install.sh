#!/bin/sh
# 把本仓库安装为 AI 技能。
# 用法：
#   ./install.sh              # 自动探测 ~/.workbuddy/skills、~/.claude/skills、~/.codex/skills
#   ./install.sh <技能目录>    # 指定目录，例如 ~/.claude/skills
set -e

SRC=$(cd "$(dirname "$0")" && pwd)
NAME=kindle-koreader-screensaver

if [ -n "$1" ]; then
    DEST_ROOT="$1"
else
    DEST_ROOT=""
    for d in "$HOME/.workbuddy/skills" "$HOME/.claude/skills" "$HOME/.codex/skills"; do
        if [ -d "$d" ]; then
            DEST_ROOT="$d"
            break
        fi
    done
    if [ -z "$DEST_ROOT" ]; then
        echo "没找到已存在的技能目录，请手动指定：./install.sh ~/.claude/skills" >&2
        exit 1
    fi
fi

mkdir -p "$DEST_ROOT"
DEST="$DEST_ROOT/$NAME"

if [ "$SRC" != "$DEST" ]; then
    rm -rf "$DEST"
    mkdir -p "$DEST"
    cp -R "$SRC"/. "$DEST"/
fi

if [ ! -f "$DEST/SKILL.md" ]; then
    echo "安装失败：$DEST/SKILL.md 不存在" >&2
    exit 1
fi

echo "已安装到 $DEST"
echo "在 AI 对话里说「给我的 Kindle 做屏保」即可触发。"
