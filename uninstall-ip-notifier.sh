#!/bin/bash
set -u

INSTALL_PATH="/usr/local/libexec/ip-notifier-telegram"
UNINSTALL_PATH="/usr/local/libexec/uninstall-ip-notifier"
SHORTCUT_PATH="/usr/local/bin/ip"
DIRECT_PATH="/usr/local/bin/ip-notifier-telegram"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "错误：卸载需要 root 权限，请使用 root 用户运行。"
    exit 1
fi

echo "=== Telegram 公网 IP 变更通知卸载程序 ==="
echo ""
read -rp "确定要卸载脚本和 ip 快捷命令吗？[y/N]：" confirm
case "$confirm" in
    y|Y|yes|YES) ;;
    *)
        echo "已取消卸载。"
        exit 0
        ;;
esac

echo "正在停止后台监测进程..."
for pid in $(pgrep -f "${INSTALL_PATH} --run-monitor" 2>/dev/null || true); do
    [ "$pid" = "$$" ] || kill "$pid" 2>/dev/null || true
done

rm -f "$SHORTCUT_PATH" "$DIRECT_PATH" "$INSTALL_PATH" "$UNINSTALL_PATH"

echo "脚本和 ip 快捷命令已卸载。"
echo ""
read -rp "是否同时删除当前用户的配置、状态和日志文件？[y/N]：" remove_data
case "$remove_data" in
    y|Y|yes|YES)
        rm -f "$HOME/.ip-notifier.conf.enc" \
            "$HOME/.ip-notifier.state" \
            "$HOME/.ip-notifier.log"
        echo "配置、状态和日志已删除。"
        ;;
    *)
        echo "已保留配置、状态和日志文件。"
        ;;
esac

echo "卸载完成。"
