#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "Bạn phải chạy script với quyền root hoặc sudo." >&2
  exit 1
fi

# Hàm hiển thị thông tin cấu hình
show_info() {
    echo
    echo "========================================"
    echo "THÔNG TIN HỆ THỐNG"
    echo "----------------------------------------"
    echo "Hostname            : $(hostname)"
    echo "Hệ điều hành        : $(lsb_release -d | cut -f2-)"
    echo "Kernel              : $(uname -r)"
    echo "CPU                 : $(lscpu | grep 'Model name' | awk -F ':' '{print $2}' | xargs)"
    echo "Số core CPU         : $(nproc)"
    echo "RAM                 : $(free -h | awk '/Mem:/ {print $2}')"
    echo "Swap                : $(swapon --show | awk '/swapfile/ {print $3}' || echo 'Không có')"
    echo "IP công cộng        : $(curl -s ifconfig.me || wget -qO- ifconfig.me)"

    echo
    echo "========================================"
    echo "CẤU HÌNH HỆ THỐNG"
    echo "----------------------------------------"

    # Các giá trị sysctl
    echo "[sysctl.conf]"
    for key in \
      vm.swappiness \
      vm.dirty_ratio \
      vm.dirty_background_ratio \
      vm.dirty_expire_centisecs \
      vm.dirty_writeback_centisecs \
      vm.vfs_cache_pressure \
      fs.file-max \
      net.core.default_qdisc \
      net.ipv4.tcp_congestion_control
    do
        grep "^$key" /etc/sysctl.conf || echo "$key: Không có trong cấu hình"
    done

    # Cấu hình Docker
    echo
    echo "[Docker]"
    if [ -f /etc/docker/daemon.json ]; then
        jq -r 'to_entries[] | 
          if (.value|type=="object") then 
            .key+":\n" + (.value|to_entries[] | "  \(.key): \(.value)") 
          elif (.value|type=="array") then 
            .key+": " + (.value|join(", ")) 
          else 
            .key+": " + (.value|tostring) 
          end' /etc/docker/daemon.json
    else
        echo "Chưa có cấu hình daemon.json"
    fi

    # DNS
    echo
    echo "[DNS]"
    grep '^nameserver' /etc/resolv.conf || echo "Không có cấu hình nameserver"

    # Thời gian
    echo
    echo "[Thời gian hệ thống]"
    timedatectl | grep "Time zone" | awk '{print $3}'
    echo
    echo "[Chrony]"
    if systemctl list-unit-files | grep -q chrony; then
        echo "Trạng thái: $(systemctl is-active chrony)"
        echo "Tự động chạy: $(systemctl is-enabled chrony)"
    else
        echo "Chrony chưa được cài đặt"
    fi

    # Swap
    echo
    echo "[Swap]"
    swapon --show | grep swapfile | awk '{print "File: "$1", Kích thước: "$3}' || echo "Không có swapfile"

    # Phần mềm đã cài đặt
    echo
    echo "[Phần mềm đã cài đặt]"
    installed_apps=()
    for app in curl wget git htop unzip nano zip zstd jq docker
    do
        if command -v $app >/dev/null; then
            installed_apps+=("$app")
        fi
    done
    echo "${installed_apps[*]}"
}

# Kiểm tra tham số --info
if [[ "$1" == "--info" ]]; then
    show_info
    exit 0
fi

# Thư mục chứa backup
BACKUP_DIR="/opt/vps-setup-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Hàm backup file nếu tồn tại
backup_file() {
    if [ -f "$1" ]; then
        cp "$1" "$BACKUP_DIR/"
        echo "Đã backup: $1"
    else
        echo "Bỏ qua (không tồn tại): $1"
    fi
}

# Backup các file cấu hình quan trọng
backup_file "/etc/hosts"
backup_file "/etc/sysctl.conf"
backup_file "/etc/fstab"
backup_file "/etc/resolv.conf"
backup_file "/etc/docker/daemon.json"

# Tạo script khôi phục
create_restore_script() {
    cat > "$BACKUP_DIR/restore.sh" << 'EOF'
#!/bin/bash
echo "=== Khôi phục cấu hình hệ thống ==="

# Dừng Docker trước nếu đang chạy
if systemctl is-active --quiet docker; then
    echo "Dừng Docker..."
    systemctl stop docker
fi

# Mở khóa /etc/resolv.conf nếu cần
if lsattr /etc/resolv.conf 2>/dev/null | grep -q '\-i\-'; then
    chattr -i /etc/resolv.conf
    echo "Đã mở khóa /etc/resolv.conf"
fi

# Khôi phục các file nếu có
restore_file() {
    SRC="./$1"
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

# Khôi phục daemon.json hoặc tạo mặc định
if [ -f ./daemon.json ]; then
    cp ./daemon.json /etc/docker/daemon.json
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

# Kiểm tra cấu hình daemon.json
if ! jq . /etc/docker/daemon.json >/dev/null 2>&1; then
    echo "⚠️  Lỗi cú pháp trong daemon.json. KHÔNG khởi động Docker."
    exit 1
fi

# Bắt đầu lại Docker
echo "Khởi động lại Docker..."
systemctl start docker

echo "✅ Hoàn tất khôi phục."
EOF

    chmod +x "$BACKUP_DIR/restore.sh"
    echo "Đã tạo script restore tại: $BACKUP_DIR/restore.sh"
}

create_restore_script


# Hàm xóa các dòng có pattern trong file
remove_sysctl_lines() {
    local file=$1
    shift
    for pattern in "$@"; do
        # Xóa dòng chứa pattern trong file
        sed -i "/$pattern/d" "$file"
    done
}

# Kiểm tra và thêm hostname vào file /etc/hosts
hostname=$(hostname)
localhost_ip="127.0.0.1"
hosts_file="/etc/hosts"
if grep -q "$hostname" "$hosts_file"; then
    echo "Hostname $hostname đã có trong $hosts_file."
else
    echo "Thêm hostname $hostname vào $hosts_file."
    # Thêm hostname vào file /etc/hosts
    echo "$localhost_ip $hostname" | sudo tee -a "$hosts_file" > /dev/null
    echo "Đã thêm $hostname vào $hosts_file."
fi

# Update và nâng cấp hệ thống
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
apt-get autoremove -y
apt-get clean

# Tắt firewall nếu đã cài đặt (phần này dành cho Oracle Ubuntu 22.04)
apt remove iptables-persistent -y
ufw disable
iptables -F

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
  
# Cấu hình DNS Server (khóa cứng resolv.conf để tránh bị sửa lại )
systemctl disable --now systemd-resolved
rm -f /etc/resolv.conf
echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf

# Tối ưu hóa TCP BBR
remove_sysctl_lines /etc/sysctl.conf "net.core.default_qdisc" "net.ipv4.tcp_congestion_control"
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

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

    cat <<EOF | sudo tee -a /etc/sysctl.conf > /dev/null
vm.swappiness=10
vm.dirty_ratio=$dirty_ratio
vm.dirty_background_ratio=$dirty_bg_ratio
vm.dirty_expire_centisecs=$expire
vm.dirty_writeback_centisecs=$writeback
vm.vfs_cache_pressure=$vfs_pressure
fs.file-max=$file_max
EOF

    sudo sysctl -p
}

# Hàm để tạo swapfile
create_swapfile() {
    local swap_size=$1
    if swapon --show | grep -q '/swapfile'; then
        echo "Swapfile đã tồn tại. Bỏ qua."
        return
    fi

    echo "Tạo swapfile $swap_size GB..."
    sudo fallocate -l ${swap_size}G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile

    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
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
######################################################

# Cài đặt các công cụ cơ bản
apt install -y curl wget git htop unzip nano zip zstd jq

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


show_info

echo
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
echo "#         sudo reboot now"
echo "#"
echo "######################################################"
echo
######################################################
