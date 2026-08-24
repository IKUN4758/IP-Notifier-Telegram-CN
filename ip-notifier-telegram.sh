#!/bin/bash
umask 077

CHECK_INTERVAL=60
NOTIFICATION_DELAY=5

BASE_DIR="${HOME}"
LOG_FILE="${BASE_DIR}/.ip-notifier.log"
STATE_FILE="${BASE_DIR}/.ip-notifier.state"
CONFIG_FILE="${BASE_DIR}/.ip-notifier.conf.enc"

ENABLE_LOGGING=true
FORCE_NOTIFICATION=false

BOT_TOKEN="${BOT_TOKEN:-}"
CHAT_ID="${CHAT_ID:-}"
IPINFO_TOKEN="${IPINFO_TOKEN:-}"

IP_SERVICES=(
    "https://api.ipify.org"
    "https://ifconfig.me/ip"
    "https://icanhazip.com"
    "https://api.my-ip.io/ip"
)

log_message() {
    local msg="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $msg"
    if [ "$ENABLE_LOGGING" = true ]; then
        echo "$timestamp | $msg" >> "$LOG_FILE"
    fi
}

check_requirements() {
    for cmd in curl hostname openssl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "错误：缺少必要命令：$cmd"
            exit 1
        fi
    done
}

validate_ipv6() {
    local ip="$1"
    [[ "$ip" == *:* ]] && [[ "$ip" != *[^0-9A-Fa-f:]* ]]
}

validate_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        for octet in "${BASH_REMATCH[@]:1}"; do
            if (( octet > 255 )); then
                return 1
            fi
        done
        return 0
    fi

    validate_ipv6 "$ip"
}

get_external_ip() {
    local ip=""
    for service in "${IP_SERVICES[@]}"; do
        ip=$(curl -s --max-time 5 "$service" | tr -d '[:space:]')
        if [ -n "$ip" ] && validate_ip "$ip"; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

get_local_ip() {
    local ip_local
    ip_local=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$ip_local" ]; then echo "N/A"; else echo "$ip_local"; fi
}

send_telegram() {
    local msg="$1"
    local parse_mode="${2:-Markdown}"
    local response curl_exit=0
    local -a curl_args

    curl_args=(
        curl -sS --max-time 10 -X POST
        "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
        --data-urlencode "chat_id=$CHAT_ID"
        --data-urlencode "text=$msg"
    )
    if [ -n "$parse_mode" ]; then
        curl_args+=(--data-urlencode "parse_mode=$parse_mode")
    fi

    response=$("${curl_args[@]}" 2>&1) || curl_exit=$?
    if [[ $curl_exit -eq 0 && $response == *'"ok":true'* ]]; then
        log_message "Telegram 通知发送成功。"
        return 0
    else
        log_message "Telegram 通知发送失败（curl=$curl_exit）：$response"
        return 1
    fi
}

encrypt_config() {
    local token="$1"
    local chat_id="$2"
    local ipinfo_token="$3"
    local passphrase="$4"
    printf 'BOT_TOKEN=%s\nCHAT_ID=%s\nIPINFO_TOKEN=%s\n' "$token" "$chat_id" "$ipinfo_token" | \
        openssl enc -aes-256-cbc -salt -pbkdf2 -pass "pass:${passphrase}" -out "$CONFIG_FILE" 2>/dev/null
    return $?
}

decrypt_config() {
    local passphrase="$1"
    local plaintext
    plaintext=$(openssl enc -aes-256-cbc -d -salt -pbkdf2 -pass "pass:${passphrase}" -in "$CONFIG_FILE" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    # Validate decrypted content format before loading
    if ! echo "$plaintext" | grep -q '^BOT_TOKEN=' || ! echo "$plaintext" | grep -q '^CHAT_ID='; then
        return 1
    fi
    IPINFO_TOKEN=""
    eval "$plaintext"
    return 0
}

validate_telegram_credentials() {
    local response
    response=$(curl -s --max-time 10 -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="IP 通知脚本：凭据验证成功。" 2>&1)
    if [[ $? -eq 0 && $response == *'"ok":true'* ]]; then
        return 0
    fi
    return 1
}

prompt_passphrase_decrypt() {
    local attempts=0
    local max_attempts=3
    local passphrase
    while (( attempts < max_attempts )); do
        read -rsp "请输入解锁凭据的密码：" passphrase
        echo
        if decrypt_config "$passphrase"; then
            echo "凭据加载成功。"
            return 0
        fi
        attempts=$((attempts + 1))
        echo "密码错误，剩余尝试次数：$((max_attempts - attempts))"
    done
    echo "尝试次数过多，程序退出。"
    exit 1
}

setup_credentials() {
    echo ""
    echo "=== 首次配置 ==="
    echo ""
    echo "你需要准备 Telegram Bot Token 和 Chat ID。"
    echo "请通过 @BotFather 创建机器人，并从 @userinfobot 获取 Chat ID。"
    echo ""

    read -rp "请输入 Bot Token：" input_token
    if [[ -z "$input_token" ]]; then
        echo "Bot Token 不能为空，程序退出。"
        exit 1
    fi

    read -rp "请输入 Chat ID：" input_chat_id
    if [[ -z "$input_chat_id" ]]; then
        echo "Chat ID 不能为空，程序退出。"
        exit 1
    fi

    read -rp "请输入 IPinfo Token（可留空，跳过归属地查询）：" input_ipinfo_token

    echo ""
    echo "正在测试 Telegram 凭据..."
    BOT_TOKEN="$input_token"
    CHAT_ID="$input_chat_id"
    IPINFO_TOKEN="$input_ipinfo_token"
    if ! validate_telegram_credentials; then
        echo "Telegram API 测试失败，请检查 Bot Token 和 Chat ID 是否正确。"
        exit 1
    fi
    echo "凭据验证成功。"
    echo ""

    local passphrase1 passphrase2
    read -rsp "请设置用于加密凭据的密码：" passphrase1
    echo
    read -rsp "请再次输入密码：" passphrase2
    echo

    if [[ "$passphrase1" != "$passphrase2" ]]; then
        echo "两次输入的密码不一致，程序退出。"
        exit 1
    fi
    if [[ -z "$passphrase1" ]]; then
        echo "密码不能为空，程序退出。"
        exit 1
    fi

    if encrypt_config "$BOT_TOKEN" "$CHAT_ID" "$IPINFO_TOKEN" "$passphrase1"; then
        echo "凭据已加密并保存。"
    else
        echo "凭据加密失败，程序退出。"
        exit 1
    fi
}

get_ipinfo_details() {
    local ip="$1"
    local url="https://ipinfo.io/${ip}/json"
    local details

    if [ -n "$IPINFO_TOKEN" ]; then
        url="${url}?token=${IPINFO_TOKEN}"
    fi

    details=$(curl -s --max-time 10 "$url" 2>/dev/null || true)
    [ -z "$details" ] && return 1

    printf '%s' "$details" | jq -r '
        [
            (.city // "未知"),
            (.region // "未知"),
            (.country // "未知"),
            (.loc // "未知"),
            (.org // "未知"),
            (.timezone // "未知"),
            (.hostname // "未知")
        ] | @tsv
    '
}

test_notification() {
    echo "正在获取当前公网 IP（支持 IPv4/IPv6）..."
    local current_ip
    if ! current_ip=$(get_external_ip); then
        echo "测试失败：无法获取公网 IP，请检查服务器网络或 IPv4/IPv6 出口。"
        return 1
    fi

    local local_ip hostname time ipinfo_details
    local ipinfo_city="未知" ipinfo_region="未知" ipinfo_country="未知"
    local ipinfo_loc="未知" ipinfo_org="未知" ipinfo_timezone="未知"
    local ipinfo_hostname="未知"

    local_ip=$(get_local_ip)
    hostname=$(hostname)
    time=$(date '+%Y-%m-%d %H:%M:%S')
    ipinfo_details=$(get_ipinfo_details "$current_ip" 2>/dev/null || true)
    if [ -n "$ipinfo_details" ]; then
        IFS=$'\t' read -r ipinfo_city ipinfo_region ipinfo_country ipinfo_loc ipinfo_org ipinfo_timezone ipinfo_hostname <<< "$ipinfo_details"
    fi

    local msg
    msg="公网 IP 监测测试通知

公网 IP：$current_ip
本机 IP：$local_ip
主机名：$hostname
时间：$time

IP 归属信息：
城市：$ipinfo_city
地区：$ipinfo_region
国家：$ipinfo_country
坐标：$ipinfo_loc
运营商：$ipinfo_org
时区：$ipinfo_timezone
状态：测试成功"

    echo "正在发送测试消息..."
    if send_telegram "$msg" ""; then
        echo "测试成功：Telegram 已收到测试通知。"
        return 0
    fi

    echo "测试失败：Telegram 消息发送失败，请检查 Bot Token、Chat ID 和网络。"
    return 1
}

start_monitoring() {
    log_message "开始监测公网 IP（检测间隔：${CHECK_INTERVAL} 秒）..."

    while true; do
        CURRENT_IP=$(get_external_ip)

        if [ -z "$CURRENT_IP" ]; then
            log_message "警告：暂时无法获取公网 IP，将在 ${CHECK_INTERVAL} 秒后重试..."
            sleep "$CHECK_INTERVAL"
            continue
        fi

        if [ -f "$STATE_FILE" ]; then
            LAST_IP=$(cat "$STATE_FILE")
            if ! validate_ip "$LAST_IP"; then
                log_message "警告：状态文件中的 IP 无效，将按首次运行处理。"
                LAST_IP=""
            fi
        else
            LAST_IP=""
        fi

        IP_CHANGED=false
        if [ "$CURRENT_IP" != "$LAST_IP" ]; then
            IP_CHANGED=true
        fi

        SHOULD_NOTIFY=false
        STATUS_MSG="IP 未变化"

        if [ "$FORCE_NOTIFICATION" = true ]; then
            SHOULD_NOTIFY=true
            STATUS_MSG="强制通知"
            FORCE_NOTIFICATION=false
        elif [ "$IP_CHANGED" = true ]; then
            SHOULD_NOTIFY=true
            if [ -z "$LAST_IP" ]; then
                STATUS_MSG="监测已启动（初始 IP）"
            else
                STATUS_MSG="IP 已变化"
            fi
        fi

        if [ "$SHOULD_NOTIFY" = true ]; then
            # Delay and recheck on actual IP change (not initial or forced)
            if [ "$IP_CHANGED" = true ] && [ -n "$LAST_IP" ]; then
                log_message "检测到 IP 变化（$LAST_IP -> $CURRENT_IP），等待 ${NOTIFICATION_DELAY} 秒确认..."
                sleep "$NOTIFICATION_DELAY"
                RECHECK_IP=$(get_external_ip)
                if [ -n "$RECHECK_IP" ] && [ "$RECHECK_IP" = "$LAST_IP" ]; then
                    log_message "IP 已恢复为 $LAST_IP，本次变化可能是临时波动，跳过通知。"
                    continue
                fi
                if [ -n "$RECHECK_IP" ]; then
                    CURRENT_IP="$RECHECK_IP"
                fi
            fi

            log_message "状态：$STATUS_MSG，正在发送通知..."

            LOCAL_IP=$(get_local_ip)
            HOSTNAME=$(hostname)
            TIME=$(date '+%Y-%m-%d %H:%M:%S')
            IPINFO_DETAILS=$(get_ipinfo_details "$CURRENT_IP" 2>/dev/null || true)
            if [ -n "$IPINFO_DETAILS" ]; then
                IFS="$(printf '\t')" read -r IPINFO_CITY IPINFO_REGION IPINFO_COUNTRY IPINFO_LOC IPINFO_ORG IPINFO_TIMEZONE IPINFO_HOSTNAME <<< "$IPINFO_DETAILS"
            fi

            MSG="🌐 *公网 IP 监测通知*"$'\n\n'
            MSG+="📡 *公网 IP：* \`$CURRENT_IP\`"$'\n'
            MSG+="🏠 *本机 IP：* \`$LOCAL_IP\`"$'\n'
            MSG+="💻 *主机名：* \`$HOSTNAME\`"$'\n'
            MSG+="📅 *时间：* \`$TIME\`"$'\n\n'

            if [ "$IP_CHANGED" = true ] && [ -n "$LAST_IP" ]; then
                MSG+="🔄 *旧公网 IP：* \`$LAST_IP\`"$'\n'
            fi
            if [ -n "$IPINFO_DETAILS" ]; then
                MSG+=$'\n'
                MSG+="📍 *IP 归属信息：*"$'\n'
                MSG+="城市：$IPINFO_CITY"$'\n'
                MSG+="地区：$IPINFO_REGION"$'\n'
                MSG+="国家：$IPINFO_COUNTRY"$'\n'
                MSG+="坐标：$IPINFO_LOC"$'\n'
                MSG+="运营商：$IPINFO_ORG"$'\n'
                MSG+="时区：$IPINFO_TIMEZONE"
                if [ "$IPINFO_HOSTNAME" != "未知" ]; then
                    MSG+="主机名：$IPINFO_HOSTNAME"$'\n'
                fi
            fi
            MSG+="✅ *状态：* $STATUS_MSG"

            send_telegram "$MSG"

            echo "$CURRENT_IP" > "$STATE_FILE"
            log_message "状态已更新，新的 IP 已保存。"
        else
            log_message "IP 未变化（$CURRENT_IP），不发送通知。"
        fi

        if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 1000 ]; then
            tail -n 500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
        fi

        sleep "$CHECK_INTERVAL"
    done
}

start_background() {
    echo "正在后台启动监测..."
    BOT_TOKEN="$BOT_TOKEN" CHAT_ID="$CHAT_ID" IPINFO_TOKEN="$IPINFO_TOKEN" \
        nohup "$0" --run-monitor > /dev/null 2>&1 &
    local pid=$!
    echo "监测已在后台启动，PID：${pid}"
    echo "停止命令：kill ${pid}"
    exit 0
}

reconfigure() {
    rm -f "$CONFIG_FILE"
    BOT_TOKEN=""
    CHAT_ID=""
    IPINFO_TOKEN=""
    setup_credentials
    show_menu
}

install_shortcut() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo "错误：安装 ip 快捷命令需要 root 权限，请使用 root 用户运行。"
        return 1
    fi

    local source_path="$0"
    local source_dir
    local install_dir="/usr/local/libexec"
    local bin_dir="/usr/local/bin"
    if command -v readlink > /dev/null 2>&1; then
        source_path="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
    fi
    source_dir="$(CDPATH= cd -- "$(dirname -- "$source_path")" && pwd)"

    install -d -m 755 "$install_dir" "$bin_dir"
    install -m 755 "$source_path" "$install_dir/ip-notifier-telegram"
    ln -sfn "$install_dir/ip-notifier-telegram" "$bin_dir/ip"
    ln -sfn "$install_dir/ip-notifier-telegram" "$bin_dir/ip-notifier-telegram"
    echo "安装成功，现在输入 ip 即可打开本菜单。"
}

uninstall_script() {
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
            return 0
            ;;
    esac

    local install_path="/usr/local/libexec/ip-notifier-telegram"
    echo "正在停止后台监测进程..."
    for pid in $(pgrep -f "${install_path} --run-monitor" 2>/dev/null || true); do
        [ "$pid" = "$$" ] || kill "$pid" 2>/dev/null || true
    done

    rm -f /usr/local/bin/ip /usr/local/bin/ip-notifier-telegram "$install_path"
    echo "脚本和 ip 快捷命令已卸载。"
    echo ""
    read -rp "是否同时删除当前用户的配置、状态和日志文件？[y/N]：" remove_data
    case "$remove_data" in
        y|Y|yes|YES)
            rm -f "$HOME/.ip-notifier.conf.enc" "$HOME/.ip-notifier.state" "$HOME/.ip-notifier.log"
            echo "配置、状态和日志已删除。"
            ;;
        *)
            echo "已保留配置、状态和日志文件。"
            ;;
    esac
    echo "卸载完成。"
}

uninstall_from_menu() {
    exec "$0" --uninstall
}

show_menu() {
    echo ""
    echo "=== Telegram 公网 IP 变更通知 ==="
    echo "[1] 前台开始监测"
    echo "[2] 后台开始监测"
    echo "[3] 重新配置凭据"
    echo "[4] 发送测试通知"
    echo "[5] 退出"
    echo "[6] 安装 ip 快捷命令"
    echo "[7] 卸载脚本"
    echo ""
    read -rp "请选择操作：" choice
    case "$choice" in
        1) start_monitoring ;;
        2) start_background ;;
        3) reconfigure ;;
        4) test_notification; show_menu ;;
        5) echo "程序退出。"; exit 0 ;;
        6) install_shortcut; show_menu ;;
        7) uninstall_from_menu ;;
        *) echo "无效选项。"; show_menu ;;
    esac
}

# --- Entrypoint ---
if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall_script
    exit 0
fi

check_requirements

if [[ "${1:-}" == "--run-monitor" ]]; then
    if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
        start_monitoring
    else
        echo "错误：后台模式无法获取凭据。"
        exit 1
    fi
    exit 0
fi

echo ""
echo "=== Telegram 公网 IP 变更通知 ==="

if [[ -f "$CONFIG_FILE" ]]; then
    prompt_passphrase_decrypt
else
    setup_credentials
fi

show_menu
