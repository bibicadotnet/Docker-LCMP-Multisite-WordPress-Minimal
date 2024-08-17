#!/bin/bash

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
cat <<EOF | tee -a /etc/sysctl.conf
# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl -p

# Cài đặt múi giờ Việt Nam
timedatectl set-timezone Asia/Ho_Chi_Minh

# Cấu hình DNS Server
echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf

# Tối ưu hóa TCP BBR
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# Hàm để cập nhật cấu hình sysctl
update_sysctl() {
    local ram_size=$1
    echo "Cập nhật cấu hình sysctl cho $ram_size GB RAM..."

    case $ram_size in
        0)
            # Cấu hình cho RAM < 1GB
            {
                echo "vm.swappiness=10"
                echo "vm.dirty_ratio=5"
                echo "vm.dirty_background_ratio=2"
                echo "vm.dirty_expire_centisecs=1000"
                echo "vm.dirty_writeback_centisecs=200"
                echo "vm.vfs_cache_pressure=200"
                echo "fs.file-max=30000"
            } | sudo tee -a /etc/sysctl.conf > /dev/null
            ;;
        1)
            # Cấu hình cho 1GB RAM
            {
                echo "vm.swappiness=10"
                echo "vm.dirty_ratio=10"
                echo "vm.dirty_background_ratio=5"
                echo "vm.dirty_expire_centisecs=2000"
                echo "vm.dirty_writeback_centisecs=500"
                echo "vm.vfs_cache_pressure=100"
                echo "fs.file-max=50000"
            } | sudo tee -a /etc/sysctl.conf > /dev/null
            ;;
        2)
            # Cấu hình cho 2GB RAM
            {
                echo "vm.swappiness=10"
                echo "vm.dirty_ratio=15"
                echo "vm.dirty_background_ratio=10"
                echo "vm.dirty_expire_centisecs=3000"
                echo "vm.dirty_writeback_centisecs=750"
                echo "vm.vfs_cache_pressure=75"
                echo "fs.file-max=100000"
            } | sudo tee -a /etc/sysctl.conf > /dev/null
            ;;
        4)
            # Cấu hình cho 4GB RAM
            {
                echo "vm.swappiness=10"
                echo "vm.dirty_ratio=20"
                echo "vm.dirty_background_ratio=15"
                echo "vm.dirty_expire_centisecs=4000"
                echo "vm.dirty_writeback_centisecs=1000"
                echo "vm.vfs_cache_pressure=50"
                echo "fs.file-max=150000"
            } | sudo tee -a /etc/sysctl.conf > /dev/null
            ;;
        8)
            # Cấu hình cho 8GB RAM
            {
                echo "vm.swappiness=10"
                echo "vm.dirty_ratio=25"
                echo "vm.dirty_background_ratio=20"
                echo "vm.dirty_expire_centisecs=5000"
                echo "vm.dirty_writeback_centisecs=1500"
                echo "vm.vfs_cache_pressure=50"
                echo "fs.file-max=200000"
            } | sudo tee -a /etc/sysctl.conf > /dev/null
            ;;
        24)
            # Cấu hình cho 24GB RAM
            {
                echo "vm.swappiness=10"
                echo "vm.dirty_ratio=20"
                echo "vm.dirty_background_ratio=10"
                echo "vm.dirty_expire_centisecs=5000"
                echo "vm.dirty_writeback_centisecs=1000"
                echo "vm.vfs_cache_pressure=50"
                echo "fs.file-max=200000"
            } | sudo tee -a /etc/sysctl.conf > /dev/null
            ;;
        *)
            # Nếu RAM lớn hơn 24GB, sử dụng cấu hình cho 24GB RAM
            {
                echo "vm.swappiness=10"
                echo "vm.dirty_ratio=20"
                echo "vm.dirty_background_ratio=10"
                echo "vm.dirty_expire_centisecs=5000"
                echo "vm.dirty_writeback_centisecs=1000"
                echo "vm.vfs_cache_pressure=50"
                echo "fs.file-max=200000"
            } | sudo tee -a /etc/sysctl.conf > /dev/null
            ;;
    esac

    # Áp dụng các cấu hình
    sudo sysctl -p
}

# Hàm để tạo swapfile
create_swapfile() {
    local swap_size=$1
    echo "Tạo swapfile $swap_size GB..."

    # Tạo swapfile
    sudo fallocate -l ${swap_size}G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile

    # Thêm swapfile vào fstab
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
apt install -y curl wget git htop unzip nano zip zstd

# Cài đặt Docker
curl -fsSL https://get.docker.com | sh
usermod -aG docker $(whoami)
systemctl start docker
systemctl enable docker

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
  "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF
systemctl restart docker

######################################################
# Thông báo kết quả
echo "Cấu hình VPS chạy Docker LCMP Multisite WordPress Minimal đã hoàn tất!"
echo "Cập nhật hoàn tất:"
echo "- Các thay đổi đã được thực hiện:"
echo "  - Hệ thống đã được cập nhật $hostname."
echo "  - Hệ thống đã được cập nhật và nâng cấp."
echo "  - Firewall đã được tắt."
echo "  - IPv6 đã bị tắt."
echo "  - Múi giờ đã được cài đặt thành Asia/Ho_Chi_Minh."
echo "  - DNS Server đã được cấu hình với Cloudflare, Google"
echo "  - TCP BBR đã được kích hoạt."
echo "  - Cấu hình Sysctl đã được cập nhật cho ${ram_size}GB RAM."
echo "  - Swapfile đã được tạo và kích hoạt với kích thước ${swap_size}GB."
echo "  - Cài đặt các công cụ cơ bản curl wget git htop unzip nano zip zstd."
echo "  - Cài đặt Docker và tối ưu hóa hiệu suất Docker."
######################################################