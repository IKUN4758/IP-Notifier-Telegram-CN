<div align="center">

# 🌐 Telegram 公网 IP 变更通知

_监测公网 IP 变化，并通过 Telegram 即时通知_

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Telegram](https://img.shields.io/badge/Telegram-2CA5E0?logo=telegram&logoColor=white)](https://telegram.org/)

</div>

---

## 📋 项目简介

这是一个 Bash 脚本，会定时检测服务器的公网 IPv4/IPv6 地址。当检测到 IP 发生变化时，自动通过 Telegram 发送通知。

脚本默认每 60 秒检测一次，不依赖 Cron 常驻运行，并使用状态文件记录上一次的 IP。Telegram Bot Token 和 Chat ID 会使用 OpenSSL AES-256-CBC 加密保存在本机。

## ✨ 功能

- ⚡ **持续监测**：循环检测公网 IPv4/IPv6，不需要配置 Cron。
- 🔐 **加密保存凭据**：Bot Token 和 Chat ID 使用 AES-256-CBC 加密。
- 🖥️ **中文交互菜单**：支持前台运行、后台运行和重新配置。
- 🧪 **手动测试通知**：配置完成后可立即验证 Telegram、网络和公网 IPv4 查询。
- 🔄 **自动重试**：支持多个公网 IP 查询服务，失败时自动切换。
- 🕐 **变更确认**：检测到变化后等待并重新检查，减少误报。
- 📊 **状态持久化**：重启后仍能记住上一次 IP。
- 📝 **运行日志**：日志保存在 ~/.ip-notifier.log。
- 🎯 **智能通知**：只有 IP 变化时才发送消息。
- 🛡️ **容错运行**：网络暂时异常时不会直接退出。

## 🚀 快速开始

### 1. 安装依赖

确保系统中已安装以下命令：curl、hostname、openssl、jq。

Debian/Ubuntu：

    apt update && apt install -y curl openssl jq

CentOS/RHEL：

    yum install -y curl openssl jq

### 2. 下载并运行

    wget https://raw.githubusercontent.com/IKUN4758/IP-Notifier-Telegram-CN/main/ip-notifier-telegram.sh
    chmod +x ip-notifier-telegram.sh
    ./ip-notifier-telegram.sh

如果希望以后直接输入 ip 打开菜单，直接用 root 运行主脚本，然后在菜单中选择第 6 项：

    sudo ./ip-notifier-telegram.sh

选择菜单中的第 6 项后，输入 ip 即可再次打开菜单。第 7 项可以卸载脚本。

首次运行时，配置向导会要求填写 Bot Token、Chat ID 和可选的 IPinfo Token，并设置一个用于加密凭据的密码。

Bot Token 可通过 Telegram 的 @BotFather 获取，数字 Chat ID 可通过 @userinfobot 获取。IPinfo Token 可以留空；填写后可查询更稳定的城市、地区、运营商和时区信息。

检测到 IP 变化后，脚本会调用 IPinfo 查询归属信息，并将结果一起发送到 Telegram。IPinfo Token 和 Telegram 凭据都会加密保存在本机。

注意：不要把 Bot Token 或 IPinfo Token 发给别人，也不要上传包含 Token 的配置文件。

## 🧭 启动菜单

    === Telegram 公网 IP 变更通知 ===
    [1] 前台开始监测
    [2] 后台开始监测
    [3] 重新配置凭据
    [4] 发送测试通知
    [5] 退出
    [6] 安装 ip 快捷命令
    [7] 卸载脚本

选择 4 会立即发送一条测试通知。测试不会修改 IP 状态文件。

选择 2 可以后台运行。查看进程：

    ps aux | grep ip-notifier

停止监测：

    kill <PID>

## 📂 生成的文件

脚本会在当前用户的家目录 $HOME 中生成：

    .ip-notifier.conf.enc   加密保存的 Bot Token 和 Chat ID
    .ip-notifier.state      上一次检测到的公网 IP
    .ip-notifier.log        检测记录和错误日志

## 🧹 卸载

推荐在菜单中选择第 7 项。也可以直接运行：

    sudo ./ip-notifier-telegram.sh --uninstall

卸载时可以选择是否删除 Telegram 凭据、IPinfo Token、状态和日志。现在项目只需要保留这一个 Bash 文件。

## 📄 许可证

本项目基于 MIT License 发布，原作者版权信息和许可证文件请保留。
