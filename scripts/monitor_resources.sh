 #!/bin/bash

# 资源监控脚本
# 作者: AI Assistant
# 用途: 实时监控 trustee service 进程的资源使用情况

set -e

# 配置参数
MONITOR_INTERVAL=1  # 监控间隔（秒）

# 获取项目根目录路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

OUTPUT_DIR="$PROJECT_ROOT/results/raw_data"
LOG_FILE="$PROJECT_ROOT/results/logs/resource_monitor.log"

# 确保输出目录存在
mkdir -p "$OUTPUT_DIR" "$PROJECT_ROOT/results/logs"

# 获取时间戳
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# 获取进程PID
get_process_pids() {
    local processes=("kbs" "grpc-as" "rvps" "trustee-gateway" "as-restful")
    local pids=""
    
    for process in "${processes[@]}"; do
        local pid=$(pgrep -f "$process" 2>/dev/null | head -1)
        if [ -n "$pid" ]; then
            pids="$pids $pid"
        fi
    done
    echo $pids
}

# 监控函数
monitor_resources() {
    local test_name=$1
    local duration=${2:-120}  # 默认监控120秒
    
    echo "开始资源监控: $test_name"
    echo "监控时长: ${duration}秒"
    echo "输出文件: $OUTPUT_DIR/resource_usage_${test_name}.csv"
    
    # 创建CSV头部
    local csv_file="$OUTPUT_DIR/resource_usage_${test_name}.csv"
    echo "timestamp,process,pid,cpu_percent,memory_rss_mb,memory_vms_mb,memory_percent,threads,fds" > "$csv_file"
    
    # 获取要监控的进程PID
    local pids=$(get_process_pids)
    if [ -z "$pids" ]; then
        echo "错误: 未找到 trustee 相关进程" | tee -a "$LOG_FILE"
        return 1
    fi
    
    echo "监控进程PID: $pids" | tee -a "$LOG_FILE"
    
    # 开始监控循环
    local start_time=$(date +%s)
    local end_time=$((start_time + duration))
    
    while [ $(date +%s) -lt $end_time ]; do
        local timestamp=$(get_timestamp)
        
        # 监控每个进程
        for pid in $pids; do
            # 检查进程是否还在运行
            if ! kill -0 $pid 2>/dev/null; then
                echo "警告: 进程 $pid 已停止" | tee -a "$LOG_FILE"
                continue
            fi
            
            # 获取进程信息
            local process_info=$(ps -p $pid -o comm,pid,pcpu,pmem,rss,vsz,nlwp --no-headers 2>/dev/null || echo "")
            
            if [ -n "$process_info" ]; then
                local comm=$(echo $process_info | awk '{print $1}')
                local cpu_percent=$(echo $process_info | awk '{print $3}')
                local mem_percent=$(echo $process_info | awk '{print $4}')
                local rss_kb=$(echo $process_info | awk '{print $5}')
                local vms_kb=$(echo $process_info | awk '{print $6}')
                local threads=$(echo $process_info | awk '{print $7}')
                
                # 转换内存单位为MB
                local rss_mb=$(echo "scale=2; $rss_kb / 1024" | bc)
                local vms_mb=$(echo "scale=2; $vms_kb / 1024" | bc)
                
                # 获取文件描述符数量
                local fds=0
                if [ -d "/proc/$pid/fd" ]; then
                    fds=$(ls -1 /proc/$pid/fd 2>/dev/null | wc -l)
                fi
                
                # 写入CSV
                echo "$timestamp,$comm,$pid,$cpu_percent,$rss_mb,$vms_mb,$mem_percent,$threads,$fds" >> "$csv_file"
            fi
        done
        
        # 系统整体资源使用情况
        local sys_cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
        local sys_mem_used=$(free -m | grep "Mem:" | awk '{print $3}')
        local sys_mem_total=$(free -m | grep "Mem:" | awk '{print $2}')
        local sys_mem_percent=$(echo "scale=2; $sys_mem_used * 100 / $sys_mem_total" | bc)
        
        echo "$timestamp,system,0,$sys_cpu,$sys_mem_used,$sys_mem_total,$sys_mem_percent,0,0" >> "$csv_file"
        
        sleep $MONITOR_INTERVAL
    done
    
    echo "资源监控完成: $test_name" | tee -a "$LOG_FILE"
}

# 实时监控函数（用于后台运行）
monitor_realtime() {
    local log_file="$OUTPUT_DIR/realtime_monitor.csv"
    echo "timestamp,total_cpu,total_memory_mb,kbs_cpu,kbs_memory,grpc_as_cpu,grpc_as_memory,rvps_cpu,rvps_memory,gateway_cpu,gateway_memory,as_restful_cpu,as_restful_memory" > "$log_file"
    
    echo "开始实时监控，按 Ctrl+C 停止..."
    
    while true; do
        local timestamp=$(get_timestamp)
        local data_line="$timestamp"
        
        # 系统总体资源
        local sys_cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
        local sys_mem=$(free -m | grep "Mem:" | awk '{print $3}')
        data_line="$data_line,$sys_cpu,$sys_mem"
        
        # 各个进程资源
        for process in "kbs" "grpc-as" "rvps" "trustee-gateway" "as-restful"; do
            local pid=$(pgrep -f "$process" 2>/dev/null | head -1)
            if [ -n "$pid" ]; then
                local cpu=$(ps -p $pid -o pcpu --no-headers 2>/dev/null | tr -d ' ')
                local mem=$(ps -p $pid -o rss --no-headers 2>/dev/null | awk '{print $1/1024}')
                data_line="$data_line,$cpu,$mem"
            else
                data_line="$data_line,0,0"
            fi
        done
        
        echo "$data_line" >> "$log_file"
        sleep $MONITOR_INTERVAL
    done
}

# 生成监控摘要
generate_summary() {
    local csv_file=$1
    local summary_file="${csv_file%.csv}_summary.txt"
    
    if [ ! -f "$csv_file" ]; then
        echo "错误: 文件不存在 $csv_file"
        return 1
    fi
    
    echo "=== 资源使用摘要 ===" > "$summary_file"
    echo "生成时间: $(get_timestamp)" >> "$summary_file"
    echo "" >> "$summary_file"
    
    # 使用 awk 计算统计信息
    awk -F',' '
    NR>1 && $2!="system" {
        process=$2
        cpu_sum[process] += $4
        cpu_count[process]++
        cpu_max[process] = ($4 > cpu_max[process]) ? $4 : cpu_max[process]
        
        mem_sum[process] += $5
        mem_count[process]++
        mem_max[process] = ($5 > mem_max[process]) ? $5 : mem_max[process]
    }
    END {
        print "进程资源使用统计:"
        print "----------------------------------------"
        for (p in cpu_sum) {
            printf "%-15s CPU: 平均%.2f%% 最大%.2f%% | 内存: 平均%.2fMB 最大%.2fMB\n", 
                   p, cpu_sum[p]/cpu_count[p], cpu_max[p], 
                   mem_sum[p]/mem_count[p], mem_max[p]
        }
    }' "$csv_file" >> "$summary_file"
    
    echo "摘要已生成: $summary_file"
}

# 主函数
main() {
    case "${1:-monitor}" in
        "monitor")
            local test_name=${2:-"default"}
            local duration=${3:-120}
            monitor_resources "$test_name" "$duration"
            ;;
        "realtime")
            monitor_realtime
            ;;
        "summary")
            local csv_file=${2:-"$OUTPUT_DIR/resource_usage_default.csv"}
            generate_summary "$csv_file"
            ;;
        *)
            echo "用法: $0 {monitor|realtime|summary} [参数...]"
            echo ""
            echo "命令说明:"
            echo "  monitor [test_name] [duration]  - 监控指定时长（默认120秒）"
            echo "  realtime                        - 实时监控（按Ctrl+C停止）"
            echo "  summary [csv_file]              - 生成监控摘要"
            echo ""
            echo "例子:"
            echo "  $0 monitor test_10_concurrent 180"
            echo "  $0 realtime"
            echo "  $0 summary results/raw_data/resource_usage_test.csv"
            exit 1
            ;;
    esac
}

# 信号处理
cleanup() {
    echo ""
    echo "监控已停止" | tee -a "$LOG_FILE"
    exit 0
}

trap cleanup SIGINT SIGTERM

# 执行主函数
main "$@"