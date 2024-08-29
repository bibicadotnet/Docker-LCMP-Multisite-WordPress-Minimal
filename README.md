# Docker LCMP Multisite WordPress Minimal ![Telemetry Badge](https://monitor.bibica.net/telemetry/clnzoxcy10001vy2ohi4obbi0/clzx3jnst01txia8em59ikb95.gif?url=https://github.com/bibicadotnet/Docker-LCMP-Multisite-WordPress-Minimal)


## Cấu trúc Thư mục
Xuất phát ban đầu của Docker LCMP Multisite WordPress Minimal là 1 file lcmp.sh, giúp thêm và xóa các trang chạy WordPress qua Docker nhanh hơn, hoạt động xoay quanh 1 container Caddy duy nhất, vừa dùng làm Webserver cho mọi trang, vừa dùng làm Reverse Proxy cho các dịch vụ còn lại

Ban đầu ý tưởng của mình là tách Caddy + PHP + Mariadb ở mỗi trang ra 3 container khác nhau, tách biệt hoàn toàn, có điều làm thế vấn đề tùy chỉnh port khá mệt người vì mỗi trang phải dùng 1 port khác nhau, cấu hình 1 Caddy nhiều PHP + Mariadb chỉ cần dùng port mặc định 80/443 là đủ, cấu hình lại nhanh hơn nên sau cùng mình chọn cách này

Mỗi domain sẽ có cấu hình tùy chỉnh PHP, Mariadb riêng biệt, bổ xung thêm ssl trong trường hợp cần dùng ssl từ các nguồn ngoài như Cloudflare
```
Docker_LCMP_Multisite_WordPress/
├── 📜 lcmp.sh # Script tự động hóa
├── 📁 reverse_proxy/ # Thư mục cấu hình Caddy
│ ├── 📄 Caddyfile # Cấu hình máy chủ proxy Caddy
│ └── 📄 compose.yml # Cấu hình Docker Compose cho Caddy
├── 📁 bibica.net/ # Thư mục cho trang WordPress bibica.net
│ ├── 📁 database/ # Dữ liệu cơ sở dữ liệu
│ ├── 📁 www/ # Mã nguồn và tệp của trang WordPress
│ ├── 📁 config/ # Cấu hình chung
│ │ ├── 📄 bibica.net.conf # Cấu hình domain cho bibica.net
│ │ ├── 📄 bibica.net.env # Chứa thông tin database
│ │ ├── 📁 ssl/ # Chứng chỉ SSL
│ │ │ ├── 🔑 bibica.net.key.pem # Khóa riêng SSL
│ │ │ └── 🔑 bibica.net.pem # Chứng chỉ SSL
│ │ ├── 📁 php/ # Cấu hình PHP
│ │ │ ├── 📄 php-ini-bibica.net.ini # Cấu hình PHP tùy chỉnh
│ │ │ └── 📄 zz-docker-bibica.net.conf # Cấu hình PHP-FPM
│ │ ├── 📁 mariadb/ # Cấu hình MariaDB
│ │ │ └── 📄 mariadb-bibica.net.cnf # Cấu hình MariaDB
│ │ └── 📁 build/ # Thư mục cấu hình build riêng image
│ │ └── 📁 php/ # Thư mục cấu hình PHP build
│ │ └── 📄 Dockerfile # Dockerfile cho cấu hình PHP
│ └── 📄 compose.yml # Cấu hình Docker Compose cho bibica.net
├── 📁 domain.com/ # Thư mục cho trang WordPress domain.com
├── 📁 domain2.com/ # Thư mục cho trang WordPress domain2.com
└── 📁 domain3.com/ # Thư mục cho trang WordPress domain3.com
```
## Cài đặt
Mặc định cài đặt trên 1 OS mới là được, nó sẽ tự cài đặt các thứ cần thiết để vận hành
```
sudo wget https://go.bibica.net/docker-lcmp-multisite-wordPress-minimal -O lcmp.sh && sudo chmod +x lcmp.sh && sudo ./lcmp.sh
```
Có thể xem video trên YouTube:

[![Video Thumbnail](https://img.youtube.com/vi/Dq0iSU9kzlk/maxresdefault.jpg)](https://www.youtube.com/watch?v=Dq0iSU9kzlk)

## Backup và Restore
backup.sh và restore.sh có thể sửa lại theo nhu cầu

## Update v1.1 
1. Sử dụng trực tiếp image: `bibica/wordpress-wp-cli-php8.3-fpm-alpine`, đỡ mất thời gian build lại mỗi khi tạo trang WordPress mới
2. Thêm tùy chọn 4-3. `Đặt quyền truy cập và quyền user cho WordPress bên trong domain`, chown và chmod lại thư mục WordPress, giúp sửa các lỗi nếu upload file, phân quyền lung tung
