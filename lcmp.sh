#!/bin/bash

# Lấy đường dẫn tuyệt đối của script hiện tại
SCRIPT_PATH=$(readlink -f "$0")

# Tạo alias cho script
ALIAS="alias lcmp='$SCRIPT_PATH'"

# Đảm bảo rằng .bashrc tồn tại và có quyền ghi
if [ -f ~/.bashrc ]; then
    # Thêm alias vào .bashrc nếu chưa tồn tại
    if ! grep -q "^alias lcmp=" ~/.bashrc; then
        echo "$ALIAS" >> ~/.bashrc
        echo "Bạn có thể sử dụng phím tắt 'lcmp' để gọi script này từ bất cứ đâu."
        # Tải lại cấu hình .bashrc
        if [ -n "$BASH_VERSION" ]; then
            source ~/.bashrc
        else
            echo "Cảnh báo: Không phải là Bash shell. Vui lòng khởi động lại shell để áp dụng alias."
        fi
    else
        echo "Bạn có thể sử dụng phím tắt 'lcmp' để gọi script này từ bất cứ đâu."
    fi
else
    echo ".bashrc không tồn tại. Vui lòng kiểm tra và tạo tệp .bashrc nếu cần."
fi

	
	
# Xác định thư mục chứa script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Hàm tạo cấu hình cho domain mới
create_domain() {
    read -p "Bạn muốn dùng domain nào? " DOMAIN
    DOMAIN_DIR="$SCRIPT_DIR/$DOMAIN"

    # Kiểm tra nếu thư mục đã tồn tại
    if [ -d "$DOMAIN_DIR" ]; then
        echo "Thư mục cho domain $DOMAIN đã tồn tại. Vui lòng chọn một domain khác."
        exit 1
    fi

    # Tạo cấu trúc thư mục cho domain mới
    mkdir -p "$DOMAIN_DIR"/{database,www,config}
    mkdir -p "$DOMAIN_DIR"/config/ssl
    mkdir -p "$DOMAIN_DIR"/config/php
    mkdir -p "$DOMAIN_DIR"/config/mariadb
    
    touch "$DOMAIN_DIR"/compose.yml
    touch "$DOMAIN_DIR"/config/"$DOMAIN".env
    touch "$DOMAIN_DIR"/config/"$DOMAIN".conf
    touch "$DOMAIN_DIR"/config/php/php-ini-"$DOMAIN".ini
    touch "$DOMAIN_DIR"/config/php/zz-docker-"$DOMAIN".conf
    touch "$DOMAIN_DIR"/config/mariadb/mariadb-"$DOMAIN".cnf

    # Tạo nội dung cho compose.yml
    cat <<EOL > "$DOMAIN_DIR"/compose.yml
services:
  database.$DOMAIN:
    image: mariadb:10.11.8-ubi9
    container_name: database.$DOMAIN
    restart: always
    env_file: ./config/$DOMAIN.env
    networks:
      - reverse_proxy
    volumes:
      - ./database:/var/lib/mysql
      - ./config/mariadb/mariadb-$DOMAIN.cnf:/etc/my.cnf.d/mariadb-$DOMAIN.cnf

  wordpress.$DOMAIN:
    image: wordpress:php8.3-fpm-alpine
    container_name: wordpress.$DOMAIN
    restart: always
    env_file: ./config/$DOMAIN.env
    networks:
      - reverse_proxy
    depends_on:
      - database.$DOMAIN
    volumes:
      - ./www:/var/www/html
      - ./config/php/php-ini-$DOMAIN.ini:/usr/local/etc/php/conf.d/php-ini-$DOMAIN.ini
      - ./config/mariadb/mariadb-$DOMAIN.cnf:/usr/local/etc/php-fpm.d/mariadb-$DOMAIN.cnf

networks:
  reverse_proxy:
    external: true
EOL

    # Tạo mật khẩu ngẫu nhiên cho cơ sở dữ liệu và WordPress
    PASSWORD=$(openssl rand -base64 12)

    # Tạo mật khẩu ngẫu nhiên cho root user MySQL
    ROOT_PASSWORD=$(openssl rand -base64 12)

    # Tạo nội dung cho tệp môi trường .env
    cat <<EOL > "$DOMAIN_DIR"/config/"$DOMAIN".env
######################### Wordpress #####################################
# Địa chỉ host của cơ sở dữ liệu WordPress
WORDPRESS_DB_HOST=database.$DOMAIN

# Tên cơ sở dữ liệu WordPress
WORDPRESS_DB_NAME=$DOMAIN

# Tên người dùng cơ sở dữ liệu WordPress
WORDPRESS_DB_USER=$DOMAIN

# Mật khẩu người dùng cơ sở dữ liệu WordPress
WORDPRESS_DB_PASSWORD=$PASSWORD

######################### MYSQL ##########################################
# Tên cơ sở dữ liệu MySQL
MYSQL_DATABASE=$DOMAIN

# Tên người dùng cơ sở dữ liệu MySQL
MYSQL_USER=$DOMAIN

# Mật khẩu người dùng cơ sở dữ liệu MySQL
MYSQL_PASSWORD=$PASSWORD

# Mật khẩu root của MySQL (cần được bảo mật tốt)
MYSQL_ROOT_PASSWORD=$ROOT_PASSWORD
######################### MYSQL ##########################################
EOL

	cat <<EOL > "$DOMAIN_DIR"/config/php/php-ini-"$DOMAIN".ini
; Thời gian tối đa (tính bằng giây) để thực thi một tập lệnh PHP. Nếu quá thời gian này, tập lệnh sẽ bị dừng.
max_execution_time=6000

; Thời gian tối đa (tính bằng giây) để phân tích đầu vào. Thời gian này tính từ khi bắt đầu nhận dữ liệu cho đến khi nhận đủ dữ liệu.
max_input_time=6000

; Số lượng biến đầu vào tối đa mà PHP có thể xử lý. 
max_input_vars=5000

; Giới hạn bộ nhớ tối đa (tính bằng megabyte) mà một tập lệnh PHP có thể sử dụng.
memory_limit=256M

; Kích thước tối đa (tính bằng gigabyte) của các tập tin tải lên qua PHP.
upload_max_filesize=10G

; Số lượng tập tin tối đa có thể tải lên cùng một lúc.
max_file_uploads=6000

; Kích thước tối đa (tính bằng gigabyte) của dữ liệu POST mà PHP có thể xử lý.
post_max_size=10G

; Danh sách các hàm PHP bị vô hiệu hóa, ngăn không cho sử dụng. Ở đây không có hàm nào bị vô hiệu hóa.
disable_functions=

; Kích hoạt OPcache cho PHP. OPcache giúp tăng hiệu suất bằng cách lưu trữ mã bytecode của PHP.
opcache.enable=1

; Kích hoạt OPcache cho các tập lệnh PHP khi chạy từ CLI (Command Line Interface).
opcache.enable_cli=1

; Số lượng bộ nhớ (tính bằng megabyte) mà OPcache có thể sử dụng để lưu trữ mã bytecode.
opcache.memory_consumption=128

; Kích thước (tính bằng megabyte) của bộ nhớ lưu trữ các chuỗi nội bộ trong OPcache.
opcache.interned_strings_buffer=16

; Số lượng tệp tối đa mà OPcache có thể lưu trữ trong bộ nhớ.
opcache.max_accelerated_files=100000

; Phần trăm bộ nhớ tối đa mà OPcache có thể lãng phí mà không gây ảnh hưởng đến hiệu suất.
opcache.max_wasted_percentage=10

EOL

	# Tạo nội dung cho cấu hình PHP zz-docker
cat <<EOL > "$DOMAIN_DIR"/config/php/zz-docker-"$DOMAIN".conf
[global]
; Điều chỉnh này cho biết PHP-FPM có chạy ở chế độ daemon (chạy nền) hay không. 
; Khi đặt là "no", PHP-FPM sẽ không chạy dưới nền mà sẽ chạy trong chế độ foreground (tiền trình chính).
daemonize = no

[www]
; Cổng mà PHP-FPM sẽ lắng nghe các kết nối từ web server (như Nginx hoặc Apache). 
; Ở đây, PHP-FPM lắng nghe trên cổng 9000.
listen = 9000

; Chế độ quản lý quy trình của PHP-FPM. Ở đây sử dụng chế độ "dynamic", 
; có nghĩa là số lượng quy trình sẽ được điều chỉnh tự động dựa trên tải.
pm = dynamic

; Số lượng quy trình tối đa mà PHP-FPM có thể sử dụng để xử lý yêu cầu.
; Với giá trị này, PHP-FPM có thể khởi tạo tối đa 6 quy trình.
pm.max_children = 6

; Số lượng quy trình khởi đầu khi PHP-FPM khởi động. 
; Ở đây, PHP-FPM sẽ bắt đầu với 2 quy trình.
pm.start_servers = 2

; Số lượng quy trình rảnh rỗi tối thiểu mà PHP-FPM sẽ duy trì.
; Giá trị này giúp đảm bảo rằng luôn có ít nhất 2 quy trình sẵn sàng để xử lý yêu cầu.
pm.min_spare_servers = 2

; Số lượng quy trình rảnh rỗi tối đa mà PHP-FPM sẽ duy trì.
; Nếu số quy trình rảnh rỗi vượt quá giá trị này, PHP-FPM sẽ giảm số lượng quy trình.
pm.max_spare_servers = 4
EOL

	# Tạo nội dung cho cấu hình Mariadb
cat <<EOL > "$DOMAIN_DIR"/config/mariadb/mariadb-"$DOMAIN".cnf
[mysqld]
# Số lượng thread có thể được lưu trong cache để tăng tốc độ tạo và xóa thread
thread_cache_size = 32

# Số lượng table có thể mở cùng lúc
table_open_cache = 2048

# Kích thước bộ đệm được sử dụng để sắp xếp khi thực hiện ORDER BY
sort_buffer_size = 8M

# Bật chế độ InnoDB bắt buộc
innodb = force

# Tắt thống kê InnoDB trên metadata để cải thiện hiệu năng
innodb_stats_on_metadata = OFF

# Kích thước bộ đệm log của InnoDB
innodb_log_buffer_size = 10M

# Kiểm soát việc ghi log khi giao dịch hoàn thành. Giá trị 2 giảm số lần ghi đĩa, tăng hiệu năng
innodb_flush_log_at_trx_commit = 2

# Kích thước bộ đệm được sử dụng cho các phép JOIN mà không có chỉ mục
join_buffer_size = 8M

# Kích thước gói tối đa mà máy chủ MySQL chấp nhận
max_allowed_packet = 64M

# Kích thước bộ đệm đọc ngẫu nhiên được sử dụng cho các lệnh SELECT có chỉ mục
read_rnd_buffer_size = 16M

# Kích thước bộ đệm đọc tuần tự được sử dụng cho các lệnh SELECT không có chỉ mục
read_buffer_size = 2M

# Kích thước bộ đệm được sử dụng cho các thao tác INSERT khối lớn
bulk_insert_buffer_size = 64M

# Số lượng kết nối tối đa cho phép vào MySQL
max_connections = 512

# Kích thước bộ đệm sắp xếp MyISAM khi xây dựng lại các chỉ mục
myisam_sort_buffer_size = 128M

# Sử dụng giá trị mặc định cho các cột timestamp khi không được chỉ định rõ ràng
explicit_defaults_for_timestamp = 1

# Số lượng tệp tối đa mà MySQL có thể mở
open_files_limit = 65535

# Số lượng định nghĩa bảng có thể được lưu trong cache
table_definition_cache = 1024

# Lưu các hàm người dùng được tạo bởi log bin
log_bin_trust_function_creators = 1

# Tắt ghi log bin để cải thiện hiệu năng khi không cần replication
disable_log_bin

# Ngưỡng phần trăm của các trang bẩn khi InnoDB bắt đầu xả dữ liệu ra đĩa
innodb_adaptive_flushing_lwm = 25.000000

# Gia tăng dung lượng tập tin tự động của InnoDB
innodb_autoextend_increment = 48

# Tắt hoàn toàn query cache để tăng hiệu suất cho các phiên bản MySQL hiện đại
query_cache_type = 0
query_cache_size = 0
query_cache_limit = 1048576
query_cache_min_res_unit = 4096

# Kích thước bảng heap tối đa
max_heap_table_size = 1G

# Kích thước bộ đệm chính của MyISAM
key_buffer_size = 8M

# Kích thước bảng tạm thời tối đa
tmp_table_size = 1G

# Kích thước bộ nhớ của InnoDB để lưu dữ liệu
innodb_buffer_pool_size = 128M

# Kích thước tập tin log InnoDB
innodb_log_file_size = 16M

# Phần trăm tối đa của các trang bẩn trước khi chúng bị xả ra đĩa
innodb_max_dirty_pages_pct = 70.000000

# Kích thước ngăn xếp của mỗi thread
thread_stack = 512K

# Kích thước của từng mảnh trong bộ nhớ InnoDB
innodb_buffer_pool_chunk_size = 2M

# Kích thước bộ nhớ được cấp phát trước cho mỗi giao dịch
transaction_prealloc_size = 8K
EOL

    # Tạo nội dung cho cấu hình Caddy
    cat <<EOL > "$DOMAIN_DIR"/config/"$DOMAIN".conf
www.$DOMAIN {
    redir https://$DOMAIN{uri}
}

$DOMAIN {
	#tls /data/$DOMAIN/ssl/$DOMAIN.pem /data/$DOMAIN/ssl/$DOMAIN.key.pem
    root * /srv/$DOMAIN/www
    encode zstd gzip

    php_fastcgi wordpress.$DOMAIN:9000 {
        root /var/www/html
    }
    
    file_server {
        precompressed gzip
        index index.html
    }

    import wordpress_security
    import static_header
    import header_remove
}
EOL

    # Cập nhật Caddyfile của reverse_proxy
    if ! grep -q "# Cấu hình cho website $DOMAIN" "$SCRIPT_DIR"/reverse_proxy/Caddyfile; then
        cat <<EOL >> "$SCRIPT_DIR"/reverse_proxy/Caddyfile
# Cấu hình cho website $DOMAIN
import /config/$DOMAIN/$DOMAIN.conf
EOL
    fi

    # Cập nhật cấu hình volumes trong reverse_proxy/compose.yml
    grep -qxF "../$DOMAIN/www:/srv/$DOMAIN/www" "$SCRIPT_DIR"/reverse_proxy/compose.yml || sed -i "/volumes:/a\      - ../$DOMAIN/www:/srv/$DOMAIN/www" "$SCRIPT_DIR"/reverse_proxy/compose.yml
    grep -qxF "../$DOMAIN/config/ssl:/data/$DOMAIN/ssl" "$SCRIPT_DIR"/reverse_proxy/compose.yml || sed -i "/volumes:/a\      - ../$DOMAIN/config/ssl:/data/$DOMAIN/ssl" "$SCRIPT_DIR"/reverse_proxy/compose.yml
    grep -qxF "../$DOMAIN/config/$DOMAIN.conf:/config/$DOMAIN/$DOMAIN.conf" "$SCRIPT_DIR"/reverse_proxy/compose.yml || sed -i "/volumes:/a\      - ../$DOMAIN/config/$DOMAIN.conf:/config/$DOMAIN/$DOMAIN.conf" "$SCRIPT_DIR"/reverse_proxy/compose.yml

    echo "Cấu hình cho domain $DOMAIN đã được thêm vào Caddyfile."

    # Khởi động lại reverse_proxy để áp dụng cấu hình mới
    docker compose -f "$SCRIPT_DIR"/reverse_proxy/compose.yml up -d
    echo "Đã khởi động lại Caddy để áp dụng cấu hình mới."
    
    # Khởi động lại container domain để áp dụng cấu hình mới
    docker compose -f "$DOMAIN_DIR"/compose.yml up -d
    echo "Đã khởi động lại container $DOMAIN để áp dụng cấu hình mới."    
}

delete_domain() {
    read -p "Bạn muốn xóa domain nào? " DOMAIN
    DOMAIN_DIR="$SCRIPT_DIR/$DOMAIN"

    # Kiểm tra nếu thư mục không tồn tại
    if [ ! -d "$DOMAIN_DIR" ]; then
        echo "Thư mục cho domain $DOMAIN không tồn tại. Vui lòng kiểm tra lại tên domain."
        exit 1
    fi

    # Xóa cấu hình trong Caddyfile
    sed -i "/# Cấu hình cho website $DOMAIN/,/^import \/config\/$DOMAIN\/$DOMAIN.conf/d" "$SCRIPT_DIR"/reverse_proxy/Caddyfile

    # Xóa cấu hình volumes trong reverse_proxy/compose.yml
    sed -i "/volumes:/,/^$/ {
        /$DOMAIN\/www:\/srv\/$DOMAIN\/www/d;
        /$DOMAIN\/config\/ssl:\/data\/$DOMAIN\/ssl/d;
        /$DOMAIN\/config\/$DOMAIN.conf:\/config\/$DOMAIN\/$DOMAIN.conf/d;
    }" "$SCRIPT_DIR"/reverse_proxy/compose.yml
	
	# Xóa containers và volumes của domain
    docker compose -f "$DOMAIN_DIR"/compose.yml down --volumes	
    
    # Xóa thư mục của domain
    rm -rf "$DOMAIN_DIR"
	
    
    # Xóa file cấu hình Caddy data và Caddy config còn sót lại
    rm -rf "$SCRIPT_DIR"/reverse_proxy/caddy_data/"$DOMAIN"
    rm -rf "$SCRIPT_DIR"/reverse_proxy/caddy_config/"$DOMAIN"
	echo "Đã xóa domain $DOMAIN cùng với các thứ liên quan."

    # Khởi động lại reverse_proxy để áp dụng cấu hình mới
    docker compose -f "$SCRIPT_DIR"/reverse_proxy/compose.yml up -d

    echo "Đã khởi động lại Caddy để áp dụng cấu hình mới."
}


# Hàm liệt kê các domain đã tạo
list_domains() {
    echo "Danh sách các domain đã tạo:"
	echo
    for dir in "$SCRIPT_DIR"/*; do
        if [ -d "$dir" ]; then
            domain=$(basename "$dir")
            # Kiểm tra xem thư mục có các thư mục con và tệp cấu hình cần thiết không
            if [ -d "$dir/database" ] && [ -d "$dir/www" ] && [ -d "$dir/config/ssl" ]; then
                
				echo "$domain"
				
            fi
        fi
    done
}


# Hiển thị menu chính
show_menu() {
	echo
    echo "Chọn hành động:"
    echo "1. Tạo domain mới"
    echo "2. Xóa domain"
    echo "3. Liệt kê các domain đã tạo"
    echo "4. Quản lý Docker Container"
    echo "0. Thoát"
	echo
}


# Hiển thị danh sách container
list_containers() {
    echo
    echo "Danh sách các container hiện có:"
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Networks}}\t{{.Ports}}"
    echo
}

# Quản lý Docker Containers
manage_docker() {
    while true; do
        list_containers
        echo
		echo "Chọn hành động quản lý Docker:"
        echo "1. Khởi động lại Caddy - Reverse Proxy"
        echo "2. Kiểm tra chi tiết mạng của container"
        echo "3. Khởi động lại container"
        echo "4. Dừng container"
        echo "5. Xóa container"
        echo "6. Khởi động lại tất cả các container"
        echo "7. Xóa toàn bộ các container và tất cả mọi thứ liên quan"
        echo "0. Quay lại menu chính"
        echo
        read -p "Nhập tùy chọn của bạn: " docker_option
        
        case $docker_option in
            1)
                echo "Đang khởi động lại Caddy - Reverse Proxy..."
                # Khởi động lại Caddy
                docker restart caddy
                echo "Đã khởi động lại Caddy - Reverse Proxy."
                ;;
            2)
                read -p "Nhập tên hoặc ID của container: " container_id
                if docker inspect "$container_id" &> /dev/null; then
                    docker exec "$container_id" ip addr
                else
                    echo
					echo "Container không tồn tại hoặc không hợp lệ."
                fi
                ;;
            3)
                read -p "Nhập tên hoặc ID của container: " container_id
                if docker inspect "$container_id" &> /dev/null; then
                    docker restart "$container_id"
                else
                    echo
					echo "Container không tồn tại hoặc không hợp lệ."
                fi
                ;;
            4)
                read -p "Nhập tên hoặc ID của container: " container_id
                if docker inspect "$container_id" &> /dev/null; then
                    docker stop "$container_id"
                else
                    echo
					echo "Container không tồn tại hoặc không hợp lệ."
                fi
                ;;
            5)
                read -p "Nhập tên hoặc ID của container: " container_id
                if docker inspect "$container_id" &> /dev/null; then
                    docker rm "$container_id"
                else
                    echo
					echo "Container không tồn tại hoặc không hợp lệ."
                fi
                ;;
            6)
                echo "Đang khởi động lại toàn bộ các container..."
                # Dừng tất cả các container đang chạy
                docker stop $(docker ps -q) 2>/dev/null
                # Khởi động lại tất cả các container đã dừng
                docker start $(docker ps -a -q --filter "status=exited") 2>/dev/null
				# Khởi động lại tất cả các container đang chạy (không cần thiết, chỉ nếu bạn muốn)
				docker restart $(docker ps -q) 2>/dev/null
                echo "Đã khởi động lại tất cả các container đã dừng và các container đang chạy."
                ;;
            7)
                echo "Đang xóa toàn bộ các Docker containers, images, volumes và networks..."
                docker stop $(docker ps -q) 2>/dev/null
                docker rm $(docker ps -a -q) 2>/dev/null
                docker rmi $(docker images -q) 2>/dev/null
                docker volume rm $(docker volume ls -q) 2>/dev/null
                docker network rm $(docker network ls -q) 2>/dev/null
                echo "Đã xóa toàn bộ các Docker và tất cả mọi thứ liên quan."
                ;;
            0)
                return
                ;;
            *)
                echo "Tùy chọn không hợp lệ. Vui lòng chọn lại."
                ;;
        esac
    done
}

# Xử lý tùy chọn của người dùng
while true; do
    show_menu
    read -p "Nhập tùy chọn của bạn: " option
    case $option in
        1) create_domain ;;
        2) delete_domain ;;
        3) list_domains ;;
        4) manage_docker ;;
        0) exit 0 ;;
        *) echo "Tùy chọn không hợp lệ. Vui lòng chọn lại." ;;
    esac
done

