#!/bin/bash

# 主性能测试执行脚本
# 作者: AI Assistant
# 用途: 协调执行完整的 trustee service 性能测试

set -e

# 配置参数
TEST_NAME="trustee_performance_$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="results"
LOG_FILE="$OUTPUT_DIR/logs/main_test.log"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"/{raw_data,reports,logs,charts}

# 时间戳和日志函数
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    echo "[$(get_timestamp)] $1" | tee -a "$LOG_FILE"
}

# 检查依赖
check_dependencies() {
    log "检查测试依赖..."
    
    local missing_deps=0
    
    # 检查必要命令
    local commands=("kbs-client" "python3" "htop" "iostat" "bc")
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "错误: 缺少命令 $cmd"
            ((missing_deps++))
        fi
    done
    
    # 检查 Python 包
    python3 -c "
import sys
packages = ['matplotlib', 'plotly', 'pandas', 'psutil']
missing = []
for pkg in packages:
    try:
        __import__(pkg)
    except ImportError:
        missing.append(pkg)
        
if missing:
    print('错误: 缺少 Python 包:', ', '.join(missing))
    sys.exit(1)
" || ((missing_deps++))
    
    if [ $missing_deps -gt 0 ]; then
        log "发现 $missing_deps 个依赖问题，请运行 ./scripts/install_dependencies.sh"
        exit 1
    fi
    
    log "依赖检查通过"
}

# 检查服务状态
check_services() {
    log "检查 trustee 服务状态..."
    
    # 获取脚本目录
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if ! "$script_dir/check_services.sh" > "$OUTPUT_DIR/logs/service_check.log" 2>&1; then
        log "服务状态检查失败，请查看日志: $OUTPUT_DIR/logs/service_check.log"
        exit 1
    fi
    
    log "服务状态正常"
}

# 系统信息收集
collect_system_info() {
    log "收集系统信息..."
    
    local sysinfo_file="$OUTPUT_DIR/system_info.txt"
    
    cat > "$sysinfo_file" << EOF
=== 系统信息 ===
收集时间: $(get_timestamp)
测试名称: $TEST_NAME

1. 操作系统信息:
$(uname -a)
$(cat /etc/os-release 2>/dev/null || echo "无法获取发行版信息")

2. CPU 信息:
$(lscpu | grep -E "(Architecture|CPU op-mode|Byte Order|CPU\(s\)|Thread|Core|Socket|Model name|CPU MHz|BogoMIPS)" 2>/dev/null || echo "无法获取CPU信息")

3. 内存信息:
$(free -h)

4. 磁盘信息:
$(df -h)

5. 网络接口:
$(ip addr show | grep -E "(inet |link/ether)" || echo "无法获取网络信息")

6. 系统负载:
$(uptime)

7. 运行中的 trustee 进程:
$(ps aux | grep -E "(kbs|grpc-as|rvps|trustee-gateway)" | grep -v grep || echo "未找到相关进程")

EOF
    
    log "系统信息已保存到: $sysinfo_file"
}

# 执行性能测试
run_performance_tests() {
    log "开始执行性能测试..."
    
    # 并发量级别
    local concurrency_levels=(5 10 15 20 25 30 40 50 60 70 80 90 100)
    local test_duration=120  # 每个并发量测试120秒
    local warmup_time=30
    local cooldown_time=30
    
    log "测试配置: 并发量=${concurrency_levels[*]}, 持续=${test_duration}s, 预热=${warmup_time}s, 冷却=${cooldown_time}s"
    
    # 为每个并发量执行测试
    for concurrency in "${concurrency_levels[@]}"; do
        log "执行 $concurrency 并发测试..."
        
        # 启动资源监控（后台）
        local monitor_duration=$((warmup_time + test_duration + cooldown_time))
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        
        "$script_dir/monitor_resources.sh" monitor "${TEST_NAME}_${concurrency}c" "$monitor_duration" &
        local monitor_pid=$!
        
        # 等待监控启动
        sleep 2
        
        # 执行并发测试
        local test_result=$("$script_dir/concurrent_test.sh" single "$concurrency" "$test_duration" "$warmup_time" "$cooldown_time")
        
        # 等待监控完成
        wait $monitor_pid
        
        log "$concurrency 并发测试完成，结果: $test_result"
        
        # 系统恢复时间
        log "等待系统恢复..."
        sleep 30
    done
    
    log "所有并发量测试完成"
}

# 生成测试报告
generate_reports() {
    log "生成测试报告..."
    
    # 调用 Python 报告生成脚本
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    python3 "$script_dir/generate_report.py" \
        --test-name "$TEST_NAME" \
        --data-dir "$OUTPUT_DIR/raw_data" \
        --output-dir "$OUTPUT_DIR/reports" \
        --log-file "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        log "报告生成成功"
        log "HTML报告: $OUTPUT_DIR/reports/${TEST_NAME}_report.html"
        log "PDF报告: $OUTPUT_DIR/reports/${TEST_NAME}_report.pdf"
    else
        log "报告生成失败"
        return 1
    fi
}

# 清理和归档
cleanup_and_archive() {
    log "清理和归档测试结果..."
    
    # 创建归档目录
    local archive_dir="$OUTPUT_DIR/archives"
    mkdir -p "$archive_dir"
    
    # 打包测试结果
    local archive_file="$archive_dir/${TEST_NAME}.tar.gz"
    tar -czf "$archive_file" \
        -C "$OUTPUT_DIR" \
        raw_data/resource_usage_${TEST_NAME}_*.csv \
        raw_data/concurrent_test_*_*.csv \
        raw_data/concurrent_stats_*_*.csv \
        reports/${TEST_NAME}_*.html \
        reports/${TEST_NAME}_*.pdf \
        logs/main_test.log \
        system_info.txt \
        2>/dev/null || log "警告: 部分文件打包失败"
    
    log "测试结果已归档: $archive_file"
    
    # 清理临时文件
    find "$OUTPUT_DIR/raw_data" -name "*.tmp" -delete 2>/dev/null || true
    
    log "清理完成"
}

# 发送测试完成通知（可选）
send_notification() {
    local status=$1
    local duration=$2
    
    # 这里可以添加邮件通知、Slack通知等
    log "测试状态: $status, 耗时: ${duration}秒"
    
    # 示例：写入状态文件
    cat > "$OUTPUT_DIR/test_status.json" << EOF
{
    "test_name": "$TEST_NAME",
    "status": "$status",
    "duration_seconds": $duration,
    "start_time": "$test_start_time",
    "end_time": "$(get_timestamp())",
    "output_directory": "$OUTPUT_DIR",
    "log_file": "$LOG_FILE"
}
EOF
}

# 错误处理
handle_error() {
    local exit_code=$?
    local line_number=$1
    
    log "错误: 脚本在第 $line_number 行异常退出 (退出码: $exit_code)"
    
    # 尝试停止所有后台进程
    pkill -f "monitor_resources.sh" 2>/dev/null || true
    pkill -f "concurrent_test.sh" 2>/dev/null || true
    
    # 生成错误报告
    echo "测试执行失败" > "$OUTPUT_DIR/error_report.txt"
    echo "时间: $(get_timestamp)" >> "$OUTPUT_DIR/error_report.txt"
    echo "错误位置: 第 $line_number 行" >> "$OUTPUT_DIR/error_report.txt"
    echo "退出码: $exit_code" >> "$OUTPUT_DIR/error_report.txt"
    
    send_notification "FAILED" "$(($(date +%s) - test_start_timestamp))"
    
    exit $exit_code
}

# 设置错误处理
trap 'handle_error $LINENO' ERR

# 主执行流程
main() {
    local test_start_timestamp=$(date +%s)
    local test_start_time=$(get_timestamp)
    
    log "=== Trustee Service 性能测试开始 ==="
    log "测试名称: $TEST_NAME"
    log "开始时间: $test_start_time"
    log "输出目录: $OUTPUT_DIR"
    
    # 1. 检查依赖
    check_dependencies
    
    # 2. 检查服务状态
    check_services
    
    # 3. 收集系统信息
    collect_system_info
    
    # 4. 执行性能测试
    run_performance_tests
    
    # 5. 生成报告
    generate_reports
    
    # 6. 清理和归档
    cleanup_and_archive
    
    # 7. 计算总耗时
    local test_end_timestamp=$(date +%s)
    local total_duration=$((test_end_timestamp - test_start_timestamp))
    
    log "=== 测试完成 ==="
    log "总耗时: ${total_duration}秒 ($(echo "scale=1; $total_duration/60" | bc)分钟)"
    log "测试结果目录: $OUTPUT_DIR"
    
    # 8. 发送完成通知
    send_notification "SUCCESS" "$total_duration"
    
    # 显示主要结果文件
    echo ""
    echo "=== 主要输出文件 ==="
    echo "系统信息: $OUTPUT_DIR/system_info.txt"
    echo "测试日志: $LOG_FILE"
    echo "HTML报告: $OUTPUT_DIR/reports/${TEST_NAME}_report.html"
    echo "归档文件: $OUTPUT_DIR/archives/${TEST_NAME}.tar.gz"
    echo ""
    echo "查看报告命令: firefox $OUTPUT_DIR/reports/${TEST_NAME}_report.html"
}

# 使用方法
usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示帮助信息"
    echo "  --dry-run      只检查环境，不执行测试"
    echo "  --quick        快速测试（较少并发量，较短时间）"
    echo ""
    echo "例子:"
    echo "  $0              # 执行完整测试"
    echo "  $0 --dry-run    # 检查环境"
    echo "  $0 --quick      # 快速测试"
}

# 处理命令行参数
case "${1:-}" in
    "-h"|"--help")
        usage
        exit 0
        ;;
    "--dry-run")
        log "执行环境检查..."
        check_dependencies
        check_services
        collect_system_info
        log "环境检查完成，系统准备就绪"
        exit 0
        ;;
    "--quick")
        log "执行快速测试模式..."
        # 修改测试参数为快速模式
        # 这里可以重新定义并发量和持续时间
        ;;
    "")
        # 正常执行
        ;;
    *)
        echo "未知选项: $1"
        usage
        exit 1
        ;;
esac

# 执行主函数
main "$@" 