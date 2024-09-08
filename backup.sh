#!/bin/bash

# Kiểm tra xem zstd có được cài đặt không
if ! command -v zstd &> /dev/null; then
    message="zstd không được cài đặt. Đang cài đặt zstd..."
    send_telegram_message "$message"
    
    # Cài đặt zstd dựa trên hệ điều hành
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y zstd
    elif command -v yum &> /dev/null; then
        sudo yum install -y zstd
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y zstd
    else
        message="Hệ điều hành không được hỗ trợ để tự động cài đặt zstd. Vui lòng cài đặt zstd bằng tay."
        send_telegram_message "$message"
        exit 1
    fi
fi

start=`date +%s`

# Tạo backup mỗi ngày trên VPS
mkdir -p /var/backups/lcmp
rm -f /var/backups/lcmp/backup_$(/bin/date +%d.%m.%Y).tar.zst
tar -cpf - /home var/spool/cron/crontabs/root | zstd -1 -o /var/backups/lcmp/backup_$(/bin/date +%d.%m.%Y).tar.zst

# Chuyển backup mỗi ngày vào Google Drive
rclone copy /var/backups/lcmp/backup_$(/bin/date +%d.%m.%Y).tar.zst google-drive:bibica-net/_docker_full_backup_daily --progress
rclone delete google-drive:bibica-net/_docker_full_backup_daily --min-age 10d --progress

# Tạo thêm 1 bản backup mới nhất vào _docker_direct_link_setup
rclone copy google-drive:bibica-net/_docker_full_backup_daily/backup_$(/bin/date +%d.%m.%Y).tar.zst google-drive:bibica-net/_docker_direct_link_setup --progress
rclone moveto google-drive:bibica-net/_docker_direct_link_setup/backup_$(/bin/date +%d.%m.%Y).tar.zst google-drive:bibica-net/_docker_direct_link_setup/backup.tar.zst --progress

# Chuyển backup mỗi ngày vào Cloudflare R2 (chuyển từ Google Drive sang Cloudflare R2 cho đỡ tốn băng thông VPS)
rclone copy google-drive:bibica-net/_docker_full_backup_daily/backup_$(/bin/date +%d.%m.%Y).tar.zst cloudflare-free:bibica-net-free/_docker_full_backup_daily --progress
rclone delete cloudflare-free:bibica-net-free/_docker_full_backup_daily --min-age 2d --progress

# Tạo thêm 1 bản backup mới nhất vào _docker_direct_link_setup
rclone copy cloudflare-free:bibica-net-free/_docker_full_backup_daily/backup_$(/bin/date +%d.%m.%Y).tar.zst cloudflare-free:bibica-net-free/_docker_direct_link_setup --progress
rclone moveto cloudflare-free:bibica-net-free/_docker_direct_link_setup/backup_$(/bin/date +%d.%m.%Y).tar.zst cloudflare-free:bibica-net-free/_docker_direct_link_setup/backup.tar.zst --progress

# Xóa các file backup cũ trên VPS
rm -f /var/backups/lcmp/backup_$(/bin/date +%d.%m.%Y).tar.zst

end=`date +%s`
runtime=$((end-start))

# Set up Telegram bot API and chat ID
BOT_API_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxx"
CHAT_ID="xxxxxxxxxxx"

MESSAGE="Đã tạo backup lên Google và Cloudflare, tổng thời gian: $runtime giây"
curl -s -X POST https://api.telegram.org/bot$BOT_API_KEY/sendMessage -d chat_id=$CHAT_ID -d text="$MESSAGE"
