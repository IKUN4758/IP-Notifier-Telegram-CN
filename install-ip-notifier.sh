#!/bin/bash
set -eu

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "错误：安装需要 root 权限，请使用 root 用户运行。"
    exit 1
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/ip-notifier-telegram.sh"
UNINSTALL_SCRIPT="$SCRIPT_DIR/uninstall-ip-notifier.sh"
INSTALL_DIR="/usr/local/libexec"
BIN_DIR="/usr/local/bin"

if [ ! -f "$MAIN_SCRIPT" ] || [ ! -f "$UNINSTALL_SCRIPT" ]; then
    echo "错误：请将安装脚本、主脚本和卸载脚本放在同一目录。"
    exit 1
fi

install -d -m 755 "$INSTALL_DIR" "$BIN_DIR"
install -m 755 "$MAIN_SCRIPT" "$INSTALL_DIR/ip-notifier-telegram"
install -m 755 "$UNINSTALL_SCRIPT" "$INSTALL_DIR/uninstall-ip-notifier"
ln -sfn "$INSTALL_DIR/ip-notifier-telegram" "$BIN_DIR/ip"
ln -sfn "$INSTALL_DIR/ip-notifier-telegram" "$BIN_DIR/ip-notifier-telegram"

echo "安装完成。"
echo "现在输入 ip 即可打开 Telegram 公网 IP 监测菜单。"
echo ""
exec "$INSTALL_DIR/ip-notifier-telegram"
