#!/bin/bash

set -euo pipefail
clear

# ========================================
# KIỂM TRA HỆ THỐNG
# ========================================

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Script cần chạy với quyền root hoặc sudo!" >&2
    exit 1
fi

if ! command -v dpkg >/dev/null 2>&1; then
    echo "Script này chỉ hỗ trợ hệ thống Debian/Ubuntu!" >&2
    exit 1
fi

# ========================================
# BIẾN TOÀN CỤC
# ========================================

# Danh sách các app cần cài
apps=(curl wget git htop unzip nano zip zstd jq sudo python3 net-tools lsof iputils-ping)

# Thư mục chứa backup
BACKUP_DIR="/opt/vps-setup-backup-$(date +%Y%m%d_%H%M%S)"

# ========================================
# HÀMM HIỂN THỊ THÔNG TIN HỆ THỐNG
# ========================================

show_info() {
    echo
    echo "========================================"
    echo "THÔNG TIN HỆ THỐNG"
    echo "----------------------------------------"
    echo "Hostname            : $(hostname)"
    echo "OS                  : $(lsb_release -ds 2>/dev/null || awk -F= '/^PRETTY_NAME/ {gsub(/"/,"",$2); print $2}' /etc/os-release 2>/dev/null || echo "Unknown")"
    echo "Kernel              : $(uname -r)"
    echo "Arch                : $(uname -m) ($(getconf LONG_BIT)-bit)"
    echo "CPU                 : $(awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)"
    echo "CPU Cores           : $(nproc)"
    echo "RAM                 : $(awk '/MemTotal:|MemAvailable:|MemFree:|Buffers:|Cached:/ {if($1=="MemTotal:") total=$2/1024; if($1=="MemAvailable:") avail=$2/1024; if($1=="MemFree:") free=$2/1024; if($1=="Buffers:") buffers=$2/1024; if($1=="Cached:") cached=$2/1024} END {used = total - free - buffers - cached; printf "%s total, %s used, %s available", (total<1000 ? int(total)" MB" : sprintf("%.1f GB",total/1024)), (used<1000 ? int(used)" MB" : sprintf("%.1f GB",used/1024)), (avail<1000 ? int(avail)" MB" : sprintf("%.1f GB",avail/1024))}' /proc/meminfo)"
    echo "Swap                : $(awk '/SwapTotal:|SwapFree:/ {if($1=="SwapTotal:") total=$2/1024; if($1=="SwapFree:") free=$2/1024} END {used = total - free; if(total==0) print "None total, None used, None free"; else printf "%s total, %s used, %s free", (total<1000 ? int(total)" MB" : sprintf("%.1f GB",total/1024)), (used<1000 ? int(used)" MB" : sprintf("%.1f GB",used/1024)), (free<1000 ? int(free)" MB" : sprintf("%.1f GB",free/1024))}' /proc/meminfo)"
    echo "Disk                : $(df -h / | awk 'NR==2 {print $2 " total, " $3 " used, " $4 " free"}')"
    echo "Public IP           : $(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "Unknown")"
    echo "Private IP          : $(ip -4 addr show | awk '/inet.*brd/ && !/127\.0\.0\.1/ {gsub(/\/.*/, "", $2); print $2; exit}')"
    echo "Main Interface      : $(ip -4 route show default | awk '{print $5; exit}')"
    echo "TCP CC              : $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "Unknown")"
    echo "Virtualization      : $(systemd-detect-virt 2>/dev/null || awk '/hypervisor/ {print "Yes"; exit} END {if(!found) print "None"}' /proc/cpuinfo)"
    echo "Load Average        : $(awk '{print $1", "$2", "$3}' /proc/loadavg)"
    echo "Uptime              : $(awk '{days=int($1/86400); hours=int(($1%86400)/3600); mins=int(($1%3600)/60); if(days>0) printf "%d days, ", days; if(hours>0) printf "%d hours, ", hours; printf "%d minutes", mins}' /proc/uptime)"
    echo "Location            : $(curl -s --max-time 2 ipinfo.io/city 2>/dev/null), $(curl -s --max-time 2 ipinfo.io/country 2>/dev/null)"
    echo "System Time         : $(date +'%d/%m/%Y at %I:%M %p (GMT%:z)')"

    echo
    echo "========================================"
    echo "CẤU HÌNH HỆ THỐNG"
    echo "----------------------------------------"

    # Hiển thị tất cả giá trị từ sysctl.conf (bỏ dòng trắng và comment)
    echo "[sysctl.conf]"
    grep -v '^\s*#' /etc/sysctl.conf | grep -v '^\s*$'
    echo

    # Cấu hình Docker
    DOCKER_VERSION=$(docker --version | cut -d ' ' -f 3 | tr -d ',')
    echo "[Docker $DOCKER_VERSION]"
    if [ -f /etc/docker/daemon.json ]; then
        sed -E '/^\s*\/\//d; /^\s*\/\*/,/\*\//d; /^\s*$/d' /etc/docker/daemon.json | python3 -c "import json,sys;d=json.load(sys.stdin);[print(f'{k}.{k2}={v2}') if type(v)==dict else print(f'{k}={v if type(v)!=list else \",\".join(v)}') for k,v in d.items() for k2,v2 in (v.items() if type(v)==dict else [('',v)])]"
    else
        echo "Chưa có cấu hình daemon.json"
    fi

    # DNS
    echo
    echo "[DNS]"
    grep '^nameserver' /etc/resolv.conf || echo "Không có cấu hình nameserver"

    # Chrony
    if command -v chronyc >/dev/null 2>&1; then
        echo
        echo "[Chrony]"
        status=$(chronyc tracking | awk -F': ' '/Leap status/ {print $2}')
        jitter_seconds=$(chronyc tracking | awk -F': ' '/Root dispersion/ {print $2}' | xargs)
        jitter_ms=$(awk -v val="$jitter_seconds" 'BEGIN {printf "%.2f", val * 1000}')
        
        echo "Chrony trạng thái : $status"
        [[ -n "$jitter_ms" ]] && echo "Sai số đồng bộ    : ±${jitter_ms} ms"
    else
        echo
        echo "[Chrony]"
        echo "Chrony chưa được cài đặt"
    fi

    # Phần mềm đã cài đặt
    echo
    echo "[Phần mềm đã cài đặt]"
    readarray -t installed_apps < <(for app in "${apps[@]}"; do 
        command -v "$app" >/dev/null 2>&1 && echo "$app"
    done)
    echo "${installed_apps[@]}"
    echo
}

# Kiểm tra tham số --info
if [[ "${1:-}" == "--info" ]]; then
    show_info
    exit 0
fi

# ========================================
# HÀMM BACKUP VÀ KHÔI PHỤC
# ========================================

# Hàm backup file nếu tồn tại
backup_file() {
    if [ -f "$1" ]; then
        cp "$1" "$BACKUP_DIR/"
        echo "Đã backup: $1"
    else
        echo "Bỏ qua (không tồn tại): $1"
    fi
}

# Tạo script khôi phục
create_restore_script() {
    cat > "$BACKUP_DIR/restore.sh" << 'EOF'
#!/bin/bash
echo "=== Khôi phục cấu hình hệ thống ==="

# Xác định thư mục chứa script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Dừng Docker nếu đang chạy
echo "Dừng Docker và docker.socket..."
systemctl stop docker.socket docker

# Mở khóa /etc/resolv.conf nếu cần
if lsattr /etc/resolv.conf 2>/dev/null | grep -q '\-i\-'; then
    chattr -i /etc/resolv.conf
    echo "Đã mở khóa /etc/resolv.conf"
fi

# Hàm khôi phục file
restore_file() {
    SRC="$SCRIPT_DIR/$1"
    DEST="/etc/$1"
    if [ -f "$SRC" ]; then
        cp "$SRC" "$DEST"
        echo "Khôi phục $DEST"
    else
        echo "Bỏ qua: $SRC không tồn tại"
    fi
}

restore_file "hosts"
restore_file "sysctl.conf"
restore_file "fstab"
restore_file "resolv.conf"

# Kiểm tra và thêm hostname vào file /etc/hosts
hostname=$(hostname)
localhost_ip="127.0.0.1"
hosts_file="/etc/hosts"
if grep -q "$hostname" "$hosts_file"; then
    echo "Hostname $hostname đã có trong $hosts_file."
else
    echo "Thêm hostname $hostname vào $hosts_file."
    echo "$localhost_ip $hostname" | tee -a "$hosts_file" > /dev/null
    echo "Đã thêm $hostname vào $hosts_file."
fi

echo "Reload cấu hình kernel sysctl..."
sysctl --system

echo "Mount lại các mount points (nếu có thay đổi)..."
mount -a

echo "Khởi động lại dịch vụ DNS systemd-resolved nếu có..."
if systemctl is-active --quiet systemd-resolved; then
    systemctl restart systemd-resolved
fi

# Khôi phục daemon.json
if [ -f "$SCRIPT_DIR/daemon.json" ]; then
    cp "$SCRIPT_DIR/daemon.json" /etc/docker/daemon.json
    echo "Khôi phục /etc/docker/daemon.json"
else
    echo '{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}' > /etc/docker/daemon.json
    echo "Tạo /etc/docker/daemon.json mặc định"
fi

# Kiểm tra cú pháp daemon.json
if ! jq . /etc/docker/daemon.json >/dev/null 2>&1; then
    echo "⚠️  Lỗi cú pháp trong daemon.json. KHÔNG khởi động Docker."
    exit 1
fi

# Khởi động Docker
echo "Khởi động lại Docker..."
systemctl start docker

echo "✅ Hoàn tất khôi phục."
EOF

    chmod +x "$BACKUP_DIR/restore.sh"
    echo "Đã tạo script restore tại: $BACKUP_DIR/restore.sh"
}

# Hàm xóa các dòng có pattern trong file
remove_sysctl_lines() {
    local file=$1
    shift
    for pattern in "$@"; do
        sed -i "/$pattern/d" "$file"
    done
}

# ========================================
# KHỞI TẠO BACKUP
# ========================================

mkdir -p "$BACKUP_DIR"

# Backup các file cấu hình quan trọng
backup_file "/etc/hosts"
backup_file "/etc/sysctl.conf"
backup_file "/etc/fstab"
backup_file "/etc/resolv.conf"
backup_file "/etc/docker/daemon.json"

# Tạo script khôi phục
create_restore_script

# ========================================
# CẤU HÌNH CƠ BẢN HỆ THỐNG
# ========================================

# Kiểm tra và thêm hostname vào file /etc/hosts
hostname=$(hostname)
localhost_ip="127.0.0.1"
hosts_file="/etc/hosts"
if grep -q "$hostname" "$hosts_file"; then
    echo "Hostname $hostname đã có trong $hosts_file."
else
    echo "Thêm hostname $hostname vào $hosts_file."
    echo "$localhost_ip $hostname" | tee -a "$hosts_file" > /dev/null
    echo "Đã thêm $hostname vào $hosts_file."
fi

# Cấu hình DNS Server (khóa cứng resolv.conf để tránh bị sửa lại)
systemctl disable --now systemd-resolved 2>/dev/null || true
if lsattr /etc/resolv.conf 2>/dev/null | grep -q '\-i\-'; then
    chattr -i /etc/resolv.conf
    echo "Đã mở khóa /etc/resolv.conf"
fi
rm -f /etc/resolv.conf
echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf

# ========================================
# CẬP NHẬT HỆ ĐIỀU HÀNH
# ========================================

# Chỉ cập nhật OS Ubuntu
apt-get update -y

mapfile -t upgradable_packages < <(apt list --upgradable 2>/dev/null | tail -n +2)
declare -a packages_to_upgrade=()

for pkg_info in "${upgradable_packages[@]}"; do
    pkg=$(echo "$pkg_info" | cut -d/ -f1)
    repo=$(echo "$pkg_info" | cut -d/ -f2 | awk '{print $1}' | cut -d- -f1)
    
    if [[ "$repo" =~ ^(ubuntu|updates|security|backports)$ ]]; then
        packages_to_upgrade+=("$pkg")
    fi
done

if [ ${#packages_to_upgrade[@]} -gt 0 ]; then
    apt-get install --no-install-recommends --only-upgrade -y "${packages_to_upgrade[@]}"
fi

echo "Hoàn tất quá trình cập nhật hệ điều hành!"

# Cài đặt các app thiết yếu hay dùng
sudo apt install -y "${apps[@]}"

# ========================================
# TỐI ƯU HÓA HỆ THỐNG
# ========================================

# Tắt IPv6
remove_sysctl_lines /etc/sysctl.conf "net.ipv6.conf.all.disable_ipv6" "net.ipv6.conf.default.disable_ipv6" "net.ipv6.conf.lo.disable_ipv6" "# Disable IPv6"

cat <<EOF | tee -a /etc/sysctl.conf
# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl -p

# Cài đặt múi giờ Việt Nam
timedatectl set-timezone Asia/Ho_Chi_Minh

# Cài đặt Chrony, đồng bộ thời gian
apt-get install -y chrony
systemctl start chrony
systemctl enable chrony

# Tối ưu hóa TCP BBR
remove_sysctl_lines /etc/sysctl.conf "net.core.default_qdisc" "net.ipv4.tcp_congestion_control"
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# ========================================
# TỐI ƯU HÓA THEO DUNG LƯỢNG RAM
# ========================================

# Hàm để cập nhật cấu hình sysctl
update_sysctl() {
    local ram_size=$1
    echo "Cập nhật cấu hình sysctl cho $ram_size GB RAM..."

    declare -A config=(
        [0]="5 2 1000 200 200 30000"
        [1]="10 5 2000 500 100 50000"
        [2]="15 10 3000 750 75 100000"
        [4]="20 15 4000 1000 50 150000"
        [8]="25 20 5000 1500 50 200000"
        [24]="20 10 5000 1000 50 200000"
    )

    IFS=' ' read -r dirty_ratio dirty_bg_ratio expire writeback vfs_pressure file_max <<< "${config[$ram_size]:-${config[24]}}"

    # Xóa các dòng cũ
    remove_sysctl_lines /etc/sysctl.conf "^vm\.swappiness" "^vm\.dirty_ratio" "^vm\.dirty_background_ratio" "^vm\.dirty_expire_centisecs" "^vm\.dirty_writeback_centisecs" "^vm\.vfs_cache_pressure" "^fs\.file-max"

    cat <<EOF | tee -a /etc/sysctl.conf > /dev/null
vm.swappiness=10
vm.dirty_ratio=$dirty_ratio
vm.dirty_background_ratio=$dirty_bg_ratio
vm.dirty_expire_centisecs=$expire
vm.dirty_writeback_centisecs=$writeback
vm.vfs_cache_pressure=$vfs_pressure
fs.file-max=$file_max
EOF

    sysctl -p
}

# Hàm để tạo swapfile
create_swapfile() {
    local swap_size=$1
    if swapon --show | grep -q '/swapfile'; then
        echo "Swapfile đã tồn tại. Bỏ qua."
        return
    fi

    echo "Tạo swapfile $swap_size GB..."
    fallocate -l ${swap_size}G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab > /dev/null
    fi
}

# Kiểm tra dung lượng RAM
ram_size=$(free -g | grep Mem | awk '{print $2}')

# Chọn mốc RAM thấp hơn nếu nằm trong khoảng
if [ "$ram_size" -lt 1 ]; then
    ram_size=0
    swap_size=1
elif [ "$ram_size" -le 1 ]; then
    ram_size=1
    swap_size=1
elif [ "$ram_size" -le 2 ]; then
    ram_size=2
    swap_size=2
elif [ "$ram_size" -le 4 ]; then
    ram_size=4
    swap_size=4
elif [ "$ram_size" -le 8 ]; then
    ram_size=8
    swap_size=4
elif [ "$ram_size" -le 24 ]; then
    ram_size=24
    swap_size=4
else
    ram_size=24
    swap_size=4
fi

# Gọi hàm để cập nhật cấu hình dựa trên dung lượng RAM
update_sysctl $ram_size

# Gọi hàm để tạo swapfile
create_swapfile $swap_size

# ========================================
# CÀI ĐẶT VÀ TỐI ƯU DOCKER
# ========================================

# Cài đặt Docker
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker $(whoami)
    systemctl start docker
    systemctl enable docker
else
    echo "Docker đã được cài đặt. Bỏ qua phần cài đặt."
fi

# Tối ưu hóa hiệu suất Docker
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

show_info

echo "========================================"
echo "THÔNG TIN SAO LƯU"
echo "----------------------------------------"
echo "Thư mục backup: $BACKUP_DIR"
echo "File khôi phục: $BACKUP_DIR/restore.sh"
echo "========================================"

echo
echo "######################################################"
echo "# KHUYẾN NGHỊ: KHỞI ĐỘNG LẠI HỆ THỐNG"
echo "# Để áp dụng tất cả thay đổi, vui lòng chạy lệnh:"
echo "#"
echo "#         reboot now"
echo "#"
echo "######################################################"
echo
