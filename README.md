# Docker-LCMP-Multisite-WordPress-Minimal
Docker LCMP Multisite WordPress Minimal

Docker_LCMP_Multisite_WordPress/
├── 📜 lcmp.sh
├── 📁 reverse_proxy/
│   ├── 📄 Caddyfile
│   └── 📄 compose.yml
├── 📁 bibica.net/
│   ├── 📁 database/
│   ├── 📁 www/
│   ├── 📁 config/
│   │   ├── 📄 bibica.net.conf
│   │   ├── 📄 bibica.net.env
│   │   ├── 📁 ssl/
│   │   │   ├── 🔑 bibica.net.key.pem
│   │   │   └── 🔑 bibica.net.pem
│   │   ├── 📁 php/
│   │   │   ├── 📄 php-ini-bibica.net.ini
│   │   │   └── 📄 zz-docker-bibica.net.conf
│   │   ├── 📁 mariadb/
│   │   │   └── 📄 mariadb-bibica.net.cnf
│   │   └── 📁 build/
│   │       └── 📁 php/
│   │           └── 📄 Dockerfile
│   └── 📄 compose.yml
├── 📁 domain.com/
├── 📁 domain2.com/
└── 📁 domain3.com/
