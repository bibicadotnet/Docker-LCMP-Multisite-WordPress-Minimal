# Docker-LCMP-Multisite-WordPress-Minimal
Docker LCMP Multisite WordPress Minimal

Docker_LCMP_Multisite_WordPress/
├── 📜 lcmp.sh # Script tự động hóa
├── 📁 reverse_proxy/ # Thư mục cấu hình Caddy
│   ├── 📄 Caddyfile # Cấu hình máy chủ proxy Caddy
│   └── 📄 compose.yml # Cấu hình Docker Compose cho Caddy
├── 📁 bibica.net/ # Thư mục cho trang WordPress bibica.net
│   ├── 📁 database/ # Dữ liệu cơ sở dữ liệu
│   ├── 📁 www/ # Mã nguồn và tệp của trang WordPress
│   ├── 📁 config/ # Cấu hình chung
│   │   ├── 📄 bibica.net.conf # Cấu hình domain cho bibica.net
│   │   ├── 📄 bibica.net.env # Chứa thông tin database
│   │   ├── 📁 ssl/ # Chứng chỉ SSL
│   │   │   ├── 🔑 bibica.net.key.pem # Khóa riêng SSL
│   │   │   └── 🔑 bibica.net.pem # Chứng chỉ SSL
│   │   ├── 📁 php/ # Cấu hình PHP
│   │   │   ├── 📄 php-ini-bibica.net.ini # Cấu hình PHP tùy chỉnh
│   │   │   └── 📄 zz-docker-bibica.net.conf # Cấu hình PHP-FPM
│   │   ├── 📁 mariadb/ # Cấu hình MariaDB
│   │   │   └── 📄 mariadb-bibica.net.cnf # Cấu hình MariaDB
│   │   └── 📁 build/ # Thư mục cấu hình build
│   │       └── 📁 php/ # Thư mục cấu hình PHP build
│   │           └── 📄 Dockerfile # Dockerfile cho cấu hình PHP
│   └── 📄 compose.yml # Cấu hình Docker Compose cho bibica.net
├── 📁 domain.com/ # Thư mục cho trang WordPress domain.com
├── 📁 domain2.com/ # Thư mục cho trang WordPress domain2.com
└── 📁 domain3.com/ # Thư mục cho trang WordPress domain3.com
