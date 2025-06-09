#!/bin/bash

# Kernel Network Performance Benchmark
# Sử dụng iperf3 localhost để test kernel TCP/IP stack

LOG_FILE="kernel_benchmark_$(date +%Y%m%d_%H%M%%S).txt"
KERNEL_VERSION=$(uname -r)
RUNS=30
TEST_DURATION=15

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    local message="[$(date '+%H:%M:%S')] INFO: $1"
    echo -e "${BLUE}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

log_result() {
    local message="[$(date '+%H:%M:%S')] RESULT: $1"
    echo -e "${GREEN}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

log_summary() {
    local message="[$(date '+%H:%M:%S')] SUMMARY: $1"
    echo -e "${YELLOW}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

log_error() {
    local message="[$(date '+%H:%M:%S')] ERROR: $1"
    echo -e "${RED}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

# Kiểm tra iperf3
if ! command -v iperf3 &> /dev/null; then
    echo -e "${RED}iperf3 chưa được cài đặt. Đang cài đặt...${NC}"
    if command -v apt &> /dev/null; then
        apt update && apt install -y iperf3
    elif command -v yum &> /dev/null; then
        yum install -y iperf3
    elif command -v dnf &> /dev/null; then
        dnf install -y iperf3
    else
        log_error "Không thể tự động cài đặt iperf3. Vui lòng cài đặt thủ công."
        exit 1
    fi
fi

# Kiểm tra bc command
if ! command -v bc &> /dev/null; then
    echo -e "${RED}bc chưa được cài đặt. Đang cài đặt...${NC}"
    if command -v apt &> /dev/null; then
        apt update && apt install -y bc
    elif command -v yum &> /dev/null; then
        yum install -y bc
    elif command -v dnf &> /dev/null; then
        dnf install -y bc
    fi
fi

echo "============================================="
echo "    KERNEL NETWORK PERFORMANCE BENCHMARK"
echo "============================================="
echo "=============================================" >> "$LOG_FILE"
echo "    KERNEL NETWORK PERFORMANCE BENCHMARK" >> "$LOG_FILE"
echo "=============================================" >> "$LOG_FILE"

log_info "Hostname: $(hostname)"
log_info "OS: $(lsb_release -ds 2>/dev/null || awk -F= '/^PRETTY_NAME/ {gsub(/\"/, "", $2); print $2}' /etc/os-release 2>/dev/null || echo "Unknown")"
log_info "Kernel: $(uname -r)"
log_info "Arch: $(uname -m) ($(getconf LONG_BIT)-bit)"
log_info "CPU: $(awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)"
log_info "CPU Cores: $(nproc)"
log_info "RAM: $(awk '/MemTotal:|MemAvailable:|MemFree:|Buffers:|Cached:/ {if($1=="MemTotal:") total=$2/1024; if($1=="MemAvailable:") avail=$2/1024; if($1=="MemFree:") free=$2/1024; if($1=="Buffers:") buffers=$2/1024; if($1=="Cached:") cached=$2/1024} END {used = total - free - buffers - cached; printf "%s total, %s used, %s available", (total<1000 ? int(total)" MB" : sprintf("%.1f GB",total/1024)), (used<1000 ? int(used)" MB" : sprintf("%.1f GB",used/1024)), (avail<1000 ? int(avail)" MB" : sprintf("%.1f GB",avail/1024))}' /proc/meminfo)"
log_info "Swap: $(awk '/SwapTotal:|SwapFree:/ {if($1=="SwapTotal:") total=$2/1024; if($1=="SwapFree:") free=$2/1024} END {used = total - free; if(total==0) print "None total, None used, None free"; else printf "%s total, %s used, %s free", (total<1000 ? int(total)" MB" : sprintf("%.1f GB",total/1024)), (used<1000 ? int(used)" MB" : sprintf("%.1f GB",used/1024)), (free<1000 ? int(free)" MB" : sprintf("%.1f GB",free/1024))}' /proc/meminfo)"
log_info "Disk: $(df -h / | awk 'NR==2 {print $2 " total, " $3 " used, " $4 " free"}')"
log_info "Public IP: $(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "Unknown")"
log_info "Private IP: $(ip -4 addr show | awk '/inet.*brd/ && !/127\.0\.0\.1/ {gsub(/\/.*/, "", $2); print $2; exit}')"
log_info "Main Interface: $(ip -4 route show default | awk '{print $5; exit}')"
log_info "TCP CC: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "Unknown")"
log_info "Virtualization: $(systemd-detect-virt 2>/dev/null || awk '/hypervisor/ {print "Yes"; exit} END {if(!found) print "None"}' /proc/cpuinfo)"
log_info "Load Average: $(awk '{print $1", "$2", "$3}' /proc/loadavg)"
log_info "Uptime: $(awk '{days=int($1/86400); hours=int(($1%86400)/3600); mins=int(($1%3600)/60); if(days>0) printf "%d days, ", days; if(hours>0) printf "%d hours, ", hours; printf "%d minutes", mins}' /proc/uptime)"
log_info "Location: $(curl -s --max-time 2 ipinfo.io/city 2>/dev/null), $(curl -s --max-time 2 ipinfo.io/country 2>/dev/null)"
log_info "System Time: $(date +'%d/%m/%Y at %I:%M %p (GMT%:z)')"
log_info "Test runs: $RUNS x ${TEST_DURATION}s each"

echo "---------------------------------------------"
echo "---------------------------------------------" >> "$LOG_FILE"

# Cleanup any existing iperf3 processes
pkill iperf3 2>/dev/null
sleep 2

# Start iperf3 server
log_info "Starting iperf3 server..."
iperf3 -s -D -p 5201 > /dev/null 2>&1
sleep 3

# Kiểm tra server có chạy không
if ! pgrep iperf3 > /dev/null; then
    log_error "Không thể start iperf3 server"
    exit 1
fi

log_info "Server started successfully"

# Arrays để lưu kết quả
tcp_results=()

# Function để extract throughput từ iperf3 output
extract_throughput() {
    local output="$1"
    
    # Tìm SUM line cho receiver
    local sum_line=$(echo "$output" | grep "SUM.*receiver" | tail -1)
    
    if [ -n "$sum_line" ]; then
        # Parse format: [SUM] 0.00-15.05 sec 4.63 GBytes 3.95 Gbits/sec receiver
        local value=$(echo "$sum_line" | awk '{
            for(i=1; i<=NF; i++) {
                if($i ~ /bits\/sec$/) {
                    value = $(i-1);
                    unit = $i;
                    # Convert to Gbps
                    if (unit == "Mbits/sec") value = value / 1000;
                    else if (unit == "Kbits/sec") value = value / 1000000;
                    else if (unit == "bits/sec") value = value / 1000000000;
                    printf "%.2f", value;
                    break;
                }
            }
        }')
        echo "$value"
    else
        # Fallback: try single connection receiver line
        local receiver_line=$(echo "$output" | grep "receiver" | grep -v "SUM" | tail -1)
        if [ -n "$receiver_line" ]; then
            local value=$(echo "$receiver_line" | awk '{
                for(i=1; i<=NF; i++) {
                    if($i ~ /bits\/sec$/) {
                        value = $(i-1);
                        unit = $i;
                        # Convert to Gbps
                        if (unit == "Mbits/sec") value = value / 1000;
                        else if (unit == "Kbits/sec") value = value / 1000000;
                        else if (unit == "bits/sec") value = value / 1000000000;
                        printf "%.2f", value;
                        break;
                    }
                }
            }')
            echo "$value"
        else
            echo "0"
        fi
    fi
}

# Chạy TCP tests
log_info "Bắt đầu TCP throughput tests..."
for ((i=1; i<=RUNS; i++)); do
    log_info "TCP Test $i/$RUNS..."
    
    # Chạy iperf3 và capture output
    tcp_output=$(iperf3 -c 127.0.0.1 -t $TEST_DURATION -P 4 -p 5201 2>&1)
    exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -n "$tcp_output" ]; then
        # Extract throughput
        throughput=$(extract_throughput "$tcp_output")
        
        # Debug: hiển thị raw output nếu cần
        if [ "$throughput" = "0" ] || [ -z "$throughput" ]; then
            log_info "Debug - iperf3 output sample:"
            echo "$tcp_output" | tail -5
            echo "---- Debug iperf3 output ----" >> "$LOG_FILE"
            echo "$tcp_output" | tail -5 >> "$LOG_FILE"
            echo "---- End debug output ----" >> "$LOG_FILE"
        fi
        
        # Kiểm tra throughput hợp lệ
        if [ -n "$throughput" ] && [ "$throughput" != "0" ] && [[ "$throughput" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            tcp_results+=($throughput)
            log_result "TCP Run $i: ${throughput} Gbps"
        else
            log_error "TCP Run $i: Invalid throughput result"
            tcp_results+=(0)
        fi
    else
        log_error "TCP Run $i: iperf3 failed (exit code: $exit_code)"
        tcp_results+=(0)
    fi
    
    sleep 2
done

# Tính toán thống kê TCP
tcp_valid_count=0
tcp_sum=0
tcp_min=0
tcp_max=0

if [ ${#tcp_results[@]} -gt 0 ]; then
    for result in "${tcp_results[@]}"; do
        if [ -n "$result" ] && [ "$result" != "0" ] && [[ "$result" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            if [ $tcp_valid_count -eq 0 ]; then
                tcp_min=$result
                tcp_max=$result
            fi
            
            # Use awk for floating point arithmetic
            tcp_sum=$(awk "BEGIN {print $tcp_sum + $result}")
            tcp_valid_count=$((tcp_valid_count + 1))
            
            # Update min/max
            tcp_min=$(awk "BEGIN {print ($result < $tcp_min) ? $result : $tcp_min}")
            tcp_max=$(awk "BEGIN {print ($result > $tcp_max) ? $result : $tcp_max}")
        fi
    done
    
    if [ $tcp_valid_count -gt 0 ]; then
        tcp_avg=$(awk "BEGIN {printf \"%.2f\", $tcp_sum / $tcp_valid_count}")
        
        # Tính standard deviation
        tcp_variance=0
        for result in "${tcp_results[@]}"; do
            if [ -n "$result" ] && [ "$result" != "0" ] && [[ "$result" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                diff=$(awk "BEGIN {print $result - $tcp_avg}")
                diff_sq=$(awk "BEGIN {print $diff * $diff}")
                tcp_variance=$(awk "BEGIN {print $tcp_variance + $diff_sq}")
            fi
        done
        
        tcp_variance=$(awk "BEGIN {print $tcp_variance / $tcp_valid_count}")
        tcp_stddev=$(awk "BEGIN {printf \"%.2f\", sqrt($tcp_variance)}")
        
        if [ $(awk "BEGIN {print ($tcp_avg > 0)}") -eq 1 ]; then
            tcp_cv=$(awk "BEGIN {printf \"%.2f\", ($tcp_stddev * 100) / $tcp_avg}")
        else
            tcp_cv="0"
        fi
    fi
fi

# Cleanup
log_info "Cleaning up..."
pkill iperf3 2>/dev/null

# Kết quả cuối cùng
echo ""
echo "============================================="
echo "               FINAL RESULTS"
echo "============================================="

echo "" >> "$LOG_FILE"
echo "=============================================" >> "$LOG_FILE"
echo "               FINAL RESULTS" >> "$LOG_FILE"
echo "=============================================" >> "$LOG_FILE"

log_summary "Kernel: $KERNEL_VERSION"
echo ""
echo "" >> "$LOG_FILE"

if [ $tcp_valid_count -gt 0 ]; then
    log_summary "TCP Loopback Performance:"
    log_summary "  Valid tests: $tcp_valid_count/$RUNS"
    log_summary "  Average: ${tcp_avg} Gbps"
    log_summary "  Min: ${tcp_min} Gbps" 
    log_summary "  Max: ${tcp_max} Gbps"
    log_summary "  Std Dev: ${tcp_stddev} Gbps"
    log_summary "  Coefficient of Variation: ${tcp_cv}%"
    echo ""
    echo "" >> "$LOG_FILE"
    
    # Đánh giá performance
    if [ $(awk "BEGIN {print ($tcp_avg >= 10)}") -eq 1 ]; then
        log_summary "Performance Rating: EXCELLENT (>= 10 Gbps)"
    elif [ $(awk "BEGIN {print ($tcp_avg >= 5)}") -eq 1 ]; then
        log_summary "Performance Rating: GOOD (5-10 Gbps)"
    elif [ $(awk "BEGIN {print ($tcp_avg >= 2)}") -eq 1 ]; then
        log_summary "Performance Rating: AVERAGE (2-5 Gbps)"
    else
        log_summary "Performance Rating: POOR (< 2 Gbps)"
    fi
    
    # Đánh giá consistency
    if [ $(awk "BEGIN {print ($tcp_cv <= 5)}") -eq 1 ]; then
        log_summary "Consistency: EXCELLENT (CV <= 5%)"
    elif [ $(awk "BEGIN {print ($tcp_cv <= 10)}") -eq 1 ]; then
        log_summary "Consistency: GOOD (CV <= 10%)"
    elif [ $(awk "BEGIN {print ($tcp_cv <= 20)}") -eq 1 ]; then
        log_summary "Consistency: AVERAGE (CV <= 20%)"
    else
        log_summary "Consistency: POOR (CV > 20%)"
    fi
else
    log_summary "ERROR: Không có test nào thành công!"
    log_info "Troubleshooting suggestions:"
    log_info "1. Kiểm tra iperf3 server có đang chạy: pgrep iperf3"
    log_info "2. Test thủ công: iperf3 -c 127.0.0.1 -t 5"
    log_info "3. Kiểm tra firewall và network configuration"
fi

echo ""
log_info "Kết quả đã được lưu vào: $LOG_FILE"
echo "============================================="
echo "" >> "$LOG_FILE"
echo "=============================================" >> "$LOG_FILE"
