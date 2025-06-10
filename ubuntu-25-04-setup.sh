#!/bin/bash

set -euo pipefail
clear

# ========================================
# KIỂM TRA HỆ THỐNG VÀ QUYỀN TRUY CẬP
# ========================================

# Kiểm tra quyền root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Script cần chạy với quyền root hoặc sudo!" >&2
    exit 1
fi

# Kiểm tra hệ thống Debian/Ubuntu
if ! command -v dpkg >/dev/null 2>&1; then
    echo "Script này chỉ hỗ trợ hệ thống Debian/Ubuntu!" >&2
    exit 1
fi

# Danh sách các ứng dụng cần thiết
ESSENTIAL_APPS=(
    curl wget git htop unzip nano zip zstd jq sudo 
    python3 net-tools lsof iputils-ping chrony
)

# ========================================
# HIỂN THỊ THÔNG TIN HỆ THỐNG
# ========================================

show_system_info() {
    cat <<EOF

========================================
THÔNG TIN HỆ THỐNG
----------------------------------------
Hostname            : $(hostname)
OS                  : $(lsb_release -ds 2>/dev/null || awk -F= '/^PRETTY_NAME/ {gsub(/"/,"",$2); print $2}' /etc/os-release 2>/dev/null || echo "Unknown")
Kernel              : $(uname -r)
Arch                : $(uname -m) ($(getconf LONG_BIT)-bit)
CPU                 : $(awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)
CPU Cores           : $(nproc)
RAM                 : $(awk '/MemTotal:|MemAvailable:|MemFree:|Buffers:|Cached:/ {if($1=="MemTotal:") total=$2/1024; if($1=="MemAvailable:") avail=$2/1024; if($1=="MemFree:") free=$2/1024; if($1=="Buffers:") buffers=$2/1024; if($1=="Cached:") cached=$2/1024} END {used = total - free - buffers - cached; printf "%s total, %s used, %s available", (total<1000 ? int(total)" MB" : sprintf("%.1f GB",total/1024)), (used<1000 ? int(used)" MB" : sprintf("%.1f GB",used/1024)), (avail<1000 ? int(avail)" MB" : sprintf("%.1f GB",avail/1024))}' /proc/meminfo)
Swap                : $(awk '/SwapTotal:|SwapFree:/ {if($1=="SwapTotal:") total=$2/1024; if($1=="SwapFree:") free=$2/1024} END {used = total - free; if(total==0) print "None total, None used, None free"; else printf "%s total, %s used, %s free", (total<1000 ? int(total)" MB" : sprintf("%.1f GB",total/1024)), (used<1000 ? int(used)" MB" : sprintf("%.1f GB",used/1024)), (free<1000 ? int(free)" MB" : sprintf("%.1f GB",free/1024))}' /proc/meminfo)
Disk                : $(df -h / | awk 'NR==2 {print $2 " total, " $3 " used, " $4 " free"}')
Public IP           : $(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "Unknown")
Private IP          : $(ip -4 addr show | awk '/inet.*brd/ && !/127\.0\.0\.1/ {gsub(/\/.*/, "", $2); print $2; exit}')
Main Interface      : $(ip -4 route show default | awk '{print $5; exit}')
TCP CC              : $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "Unknown")
Virtualization      : $(systemd-detect-virt 2>/dev/null || awk '/hypervisor/ {print "Yes"; exit} END {if(!found) print "None"}' /proc/cpuinfo)
Load Average        : $(awk '{print $1", "$2", "$3}' /proc/loadavg)
Uptime              : $(awk '{days=int($1/86400); hours=int(($1%86400)/3600); mins=int(($1%3600)/60); if(days>0) printf "%d days, ", days; if(hours>0) printf "%d hours, ", hours; printf "%d minutes", mins}' /proc/uptime)
Location            : $(curl -s --max-time 2 ipinfo.io/city 2>/dev/null), $(curl -s --max-time 2 ipinfo.io/country 2>/dev/null)
System Time         : $(date +'%d/%m/%Y at %I:%M %p (GMT%:z)')

========================================
CẤU HÌNH HỆ THỐNG
----------------------------------------
EOF

    # Hiển thị cấu hình IPv6
    echo "[Disable IPv6]"
    if [ -f /etc/sysctl.d/99-disable-ipv6.conf ]; then
        grep -v '^\s*#' /etc/sysctl.d/99-disable-ipv6.conf | grep -v '^\s*$'
    else
        echo "Chưa được cấu hình"
    fi
    echo

    # Hiển thị cấu hình bộ nhớ
    echo "[Memory Config]"
    if [ -f /etc/sysctl.d/99-memory-config.conf ]; then
        grep -v '^\s*#' /etc/sysctl.d/99-memory-config.conf | grep -v '^\s*$'
    else
        echo "Chưa được cấu hình"
    fi
    echo

    # Hiển thị cấu hình Docker
    if command -v docker >/dev/null 2>&1; then
        DOCKER_VERSION=$(docker --version | cut -d ' ' -f 3 | tr -d ',')
        echo "[Docker $DOCKER_VERSION]"
        if [ -f /etc/docker/daemon.json ]; then
            sed -E '/^\s*\/\//d; /^\s*\/\*/,/\*\//d; /^\s*$/d' /etc/docker/daemon.json | python3 -c "import json,sys;d=json.load(sys.stdin);[print(f'{k}.{k2}={v2}') if type(v)==dict else print(f'{k}={v if type(v)!=list else \",\".join(v)}') for k,v in d.items() for k2,v2 in (v.items() if type(v)==dict else [('',v)])]"
        else
            echo "Chưa có cấu hình daemon.json"
        fi
    else
        echo "[Docker]"
        echo "Chưa được cài đặt"
    fi

    # Hiển thị cấu hình DNS
    echo
    echo "[DNS]"
    grep '^nameserver' /etc/resolv.conf || echo "Không có cấu hình nameserver"

    # Hiển thị trạng thái Chrony
    echo
    echo "[Chrony]"
    if command -v chronyc >/dev/null 2>&1; then
        status=$(chronyc tracking 2>/dev/null | awk -F': ' '/Leap status/ {print $2}' || echo "Unknown")
        jitter_seconds=$(chronyc tracking 2>/dev/null | awk -F': ' '/Root dispersion/ {print $2}' | xargs || echo "0")
        jitter_ms=$(awk -v val="$jitter_seconds" 'BEGIN {printf "%.2f", val * 1000}')
        
        echo "Chrony trạng thái : $status"
        [[ -n "$jitter_ms" && "$jitter_ms" != "0.00" ]] && echo "Sai số đồng bộ    : ±${jitter_ms} ms"
    else
        echo "Chrony chưa được cài đặt"
    fi

    # Hiển thị danh sách phần mềm đã cài đặt
    echo
    echo "[Phần mềm đã cài đặt]"
    readarray -t installed_apps < <(for app in "${ESSENTIAL_APPS[@]}"; do 
        command -v "$app" >/dev/null 2>&1 && echo "$app"
    done)
    echo "${installed_apps[@]}"
    echo
}

# Kiểm tra tham số --info để chỉ hiển thị thông tin
if [[ "${1:-}" == "--info" ]]; then
    show_system_info
    exit 0
fi

# ========================================
# CẤU HÌNH HOSTNAME VÀ DNS
# ========================================

# Thêm hostname vào /etc/hosts nếu chưa có
HOSTNAME=$(hostname)
HOSTS_FILE="/etc/hosts"
if ! grep -q "$HOSTNAME" "$HOSTS_FILE"; then
    echo "127.0.0.1 $HOSTNAME" >> "$HOSTS_FILE"
fi

# Cấu hình DNS cố định (8.8.8.8, 1.1.1.1)
systemctl disable --now systemd-resolved 2>/dev/null || true
if lsattr /etc/resolv.conf 2>/dev/null | grep -q '\-i\-'; then
    chattr -i /etc/resolv.conf
fi
rm -f /etc/resolv.conf

cat <<EOF > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

chattr +i /etc/resolv.conf

# ========================================
# CẬP NHẬT HỆ ĐIỀU HÀNH
# ========================================

# Cập nhật danh sách gói
apt-get update -y

# Chỉ cập nhật các gói từ repository chính thức của Ubuntu
mapfile -t upgradable_packages < <(apt list --upgradable 2>/dev/null | tail -n +2)
declare -a packages_to_upgrade=()

for pkg_info in "${upgradable_packages[@]}"; do
    pkg=$(echo "$pkg_info" | cut -d/ -f1)
    repo=$(echo "$pkg_info" | cut -d/ -f2 | awk '{print $1}' | cut -d- -f1)
    
    if [[ "$repo" =~ ^(ubuntu|updates|security|backports)$ ]]; then
        packages_to_upgrade+=("$pkg")
    fi
done

# Cập nhật các gói đã chọn
if [ ${#packages_to_upgrade[@]} -gt 0 ]; then
    apt-get install --no-install-recommends --only-upgrade -y "${packages_to_upgrade[@]}"
fi

# Cài đặt các ứng dụng cần thiết
apt-get install -y "${ESSENTIAL_APPS[@]}"

# ========================================
# TỐI ƯU HÓA HỆ THỐNG
# ========================================

# Tắt IPv6 để tăng tốc độ kết nối
cat <<EOF > /etc/sysctl.d/99-disable-ipv6.conf
# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl -p /etc/sysctl.d/99-disable-ipv6.conf

# Cài đặt múi giờ Việt Nam
timedatectl set-timezone Asia/Ho_Chi_Minh

# Khởi động và kích hoạt Chrony để đồng bộ thời gian
systemctl start chrony
systemctl enable chrony

# ========================================
# TẠO VÀ CẤU HÌNH SWAP
# ========================================

# Tính toán kích thước swap dựa trên RAM
RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
SWAP_SIZE=$([ $RAM_GB -le 2 ] && echo "2G" || echo "4G")

# Xóa swap cũ nếu có
swapoff /swapfile 2>/dev/null || true
rm -f /swapfile
sed -i '/\/swapfile/d' /etc/fstab

# Tạo swap mới
fallocate -l $SWAP_SIZE /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap sw 0 0" >> /etc/fstab

# Tối ưu cấu hình bộ nhớ
cat <<EOF > /etc/sysctl.d/99-memory-config.conf
# Memory optimization
vm.swappiness = 10
EOF

sysctl -p /etc/sysctl.d/99-memory-config.conf

# ========================================
# CẤU HÌNH SSH
# ========================================

# Tăng thời gian kết nối SSH (2 giờ)
SSH_CONFIG="/etc/ssh/sshd_config"
if grep -q "^ClientAliveInterval" "$SSH_CONFIG"; then
    sed -i 's/^ClientAliveInterval.*/ClientAliveInterval 7200/' "$SSH_CONFIG"
else
    echo "ClientAliveInterval 7200" >> "$SSH_CONFIG"
fi

systemctl restart sshd

# ========================================
# CÀI ĐẶT VÀ TỐI ƯU DOCKER
# ========================================

# Cài đặt Docker nếu chưa có
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker $(whoami)
    systemctl start docker
    systemctl enable docker
fi

# Tạo cấu hình tối ưu cho Docker
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,
  "dns": ["8.8.8.8", "1.1.1.1"],
  "userland-proxy": false
}
EOF

systemctl restart docker

# ========================================
# HIỂN THỊ THÔNG TIN HOÀN TẤT
# ========================================

show_system_info

cat <<EOF

######################################################
# KHUYẾN NGHỊ: KHỞI ĐỘNG LẠI HỆ THỐNG
# Để áp dụng tất cả thay đổi, vui lòng chạy lệnh:
#
#         reboot now
#
######################################################

EOF
