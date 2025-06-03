#!/bin/bash

# Tên script: formatted_port_checker.sh
# Mô tả: Kiểm tra port và hiển thị theo định dạng:
# TCP: 22,80,443
# UDP: 53,68

# Kiểm tra quyền root
if [ "$(id -u)" -ne 0 ]; then
    echo "⚠️ Script cần chạy với quyền root. Hãy thử lại với 'sudo'." >&2
    exit 1
fi

# Kiểm tra công cụ (ss hoặc netstat)
if command -v ss &>/dev/null; then
    CMD="ss -tuln"
elif command -v netstat &>/dev/null; then
    CMD="netstat -tuln"
else
    echo "❌ Không tìm thấy ss hoặc netstat. Cài đặt một trong hai công cụ trước." >&2
    exit 1
fi

# Lấy danh sách port TCP
TCP_PORTS=$($CMD | awk '/tcp.*LISTEN/ {
    split($5, addr, ":");
    port = addr[length(addr)];
    if ($5 ~ /::/) { split($5, addr, "]:"); port = addr[2] }
    print port
}' | sort -nu | paste -sd, -)

# Lấy danh sách port UDP
UDP_PORTS=$($CMD | awk '/udp/ {
    split($5, addr, ":");
    port = addr[length(addr)];
    if ($5 ~ /::/) { split($5, addr, "]:"); port = addr[2] }
    print port
}' | sort -nu | paste -sd, -)

# Hiển thị kết quả theo định dạng yêu cầu
echo "TCP: ${TCP_PORTS:-Không có}"
echo "UDP: ${UDP_PORTS:-Không có}"
