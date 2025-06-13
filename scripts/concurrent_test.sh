 #!/bin/bash

# 并发测试脚本
# 作者: AI Assistant
# 用途: 执行不同并发量的 kbs-client 请求测试

set -e

# 配置参数
TEST_URL="http://127.0.0.1:8081/api"
TEST_COMMAND="kbs-client --url $TEST_URL attest"

# 获取项目根目录路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

OUTPUT_DIR="$PROJECT_ROOT/results/raw_data"
LOG_FILE="$PROJECT_ROOT/results/logs/concurrent_test.log"

# 确保输出目录存在
mkdir -p "$OUTPUT_DIR" "$PROJECT_ROOT/results/logs"

# 时间戳函数
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# 记录日志
log() {
    echo "[$(get_timestamp)] $1" | tee -a "$LOG_FILE"
}

# 单次请求测试
single_request() {
    local start_time=$(date +%s.%N)
    local response_code=0
    local error_msg=""
    
    # 执行请求
    if timeout 30 $TEST_COMMAND >/dev/null 2>&1; then
        response_code=200
    else
        response_code=500
        error_msg="Request failed or timeout"
    fi
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    echo "$start_time,$end_time,$duration,$response_code,$error_msg"
}

# 并发测试函数
concurrent_test() {
    local concurrency=$1
    local test_duration=${2:-120}  # 测试持续时间（秒）
    local warmup_time=${3:-30}     # 预热时间（秒）
    local cooldown_time=${4:-30}   # 冷却时间（秒）
    
    log "开始并发测试: $concurrency 并发"
    log "测试参数: 并发=$concurrency, 持续=${test_duration}s, 预热=${warmup_time}s, 冷却=${cooldown_time}s"
    
    # 创建输出文件
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local result_file="$OUTPUT_DIR/concurrent_test_${concurrency}_${timestamp}.csv"
    local stats_file="$OUTPUT_DIR/concurrent_stats_${concurrency}_${timestamp}.csv"
    
    # CSV 头部
    echo "start_time,end_time,duration,response_code,error_msg" > "$result_file"
    echo "timestamp,concurrent_requests,successful_requests,failed_requests,avg_response_time,qps" > "$stats_file"
    
    # 预热阶段
    log "预热阶段开始 (${warmup_time}秒)"
    local warmup_end=$(($(date +%s) + warmup_time))
    while [ $(date +%s) -lt $warmup_end ]; do
        for ((i=1; i<=concurrency; i++)); do
            single_request >> "$result_file" &
        done
        wait
        sleep 1
    done
    log "预热完成"
    
    # 正式测试阶段
    log "正式测试开始 (${test_duration}秒)"
    local test_start=$(date +%s)
    local test_end=$((test_start + test_duration))
    local stats_interval=10  # 每10秒统计一次
    local last_stats_time=$test_start
    
    while [ $(date +%s) -lt $test_end ]; do
        local batch_start=$(date +%s)
        
        # 启动并发请求
        for ((i=1; i<=concurrency; i++)); do
            single_request >> "$result_file" &
        done
        wait
        
        local batch_end=$(date +%s)
        local batch_duration=$((batch_end - batch_start))
        
        # 定期生成统计信息
        if [ $((batch_end - last_stats_time)) -ge $stats_interval ]; then
            generate_stats "$result_file" "$stats_file" "$concurrency" "$last_stats_time" "$batch_end"
            last_stats_time=$batch_end
        fi
        
        # 控制请求频率，避免过载
        if [ $batch_duration -lt 1 ]; then
            sleep $((1 - batch_duration))
        fi
    done
    
    log "正式测试完成"
    
    # 冷却阶段
    log "冷却阶段开始 (${cooldown_time}秒)"
    sleep $cooldown_time
    log "冷却完成"
    
    # 生成最终统计
    generate_final_stats "$result_file" "$concurrency"
    
    log "并发测试完成: $concurrency 并发"
    echo "$result_file"
}

# 生成实时统计
generate_stats() {
    local result_file=$1
    local stats_file=$2
    local concurrency=$3
    local start_time=$4
    local end_time=$5
    
    # 使用awk分析最近的请求数据
    local stats=$(awk -F',' -v start_time="$start_time" -v end_time="$end_time" '
    NR>1 && $1 >= start_time && $1 <= end_time {
        total++
        if ($4 == 200) successful++
        else failed++
        total_time += $3
    }
    END {
        if (total > 0) {
            avg_time = total_time / total
            qps = total / (end_time - start_time)
            printf "%d,%d,%d,%.3f,%.2f", total, (successful ? successful : 0), (failed ? failed : 0), avg_time, qps
        } else {
            printf "0,0,0,0,0"
        }
    }' "$result_file")
    
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$concurrency,$stats" >> "$stats_file"
}

# 生成最终统计报告
generate_final_stats() {
    local result_file=$1
    local concurrency=$2
    local report_file="${result_file%.csv}_report.txt"
    
    log "生成测试报告: $report_file"
    
    # 使用awk分析完整数据
    awk -F',' '
    BEGIN {
        print "=== 并发测试报告 ==="
        print "并发数: '$concurrency'"
        print "生成时间: " strftime("%Y-%m-%d %H:%M:%S")
        print ""
        min_start_time = 0
        max_end_time = 0
    }
    NR>1 {
        total++
        # 记录时间戳范围
        if (min_start_time == 0 || $1 < min_start_time) min_start_time = $1
        if ($2 > max_end_time) max_end_time = $2
        
        if ($4 == 200) {
            successful++
            total_success_time += $3
            if (min_time == 0 || $3 < min_time) min_time = $3
            if ($3 > max_time) max_time = $3
        } else {
            failed++
        }
        total_time += $3
    }
    END {
        success_rate = (total > 0) ? (successful / total * 100) : 0
        avg_time = (successful > 0) ? (total_success_time / successful) : 0
        overall_avg = (total > 0) ? (total_time / total) : 0
        
        print "总请求数: " total
        print "成功请求: " (successful ? successful : 0)
        print "失败请求: " (failed ? failed : 0)
        print "成功率: " sprintf("%.2f%%", success_rate)
        print ""
        print "响应时间统计 (成功请求):"
        print "  最小值: " sprintf("%.3f秒", min_time ? min_time : 0)
        print "  最大值: " sprintf("%.3f秒", max_time ? max_time : 0)
        print "  平均值: " sprintf("%.3f秒", avg_time)
        print "  总平均: " sprintf("%.3f秒", overall_avg)
        print ""
        print "性能指标:"
        if (total > 0 && max_end_time > min_start_time) {
            duration = max_end_time - min_start_time
            qps = total / duration
            print "  测试时长: " sprintf("%.1f秒", duration)
            print "  平均QPS: " sprintf("%.2f", qps)
        }
    }' "$result_file" > "$report_file"
    
    log "报告已生成: $report_file"
}

# 批量测试多个并发量
batch_test() {
    local concurrency_levels=(5 10 15 20 25 30 40 50 60 70 80 90 100)
    local test_duration=${1:-120}
    
    log "开始批量并发测试"
    log "并发量级别: ${concurrency_levels[*]}"
    
    # 创建批量测试摘要文件
    local batch_summary="$OUTPUT_DIR/batch_test_summary_$(date +%Y%m%d_%H%M%S).csv"
    echo "concurrency,total_requests,successful_requests,failed_requests,success_rate,avg_response_time,max_response_time,qps" > "$batch_summary"
    
    for concurrency in "${concurrency_levels[@]}"; do
        log "执行 $concurrency 并发测试..."
        
        # 执行单个并发量测试
        local result_file=$(concurrent_test "$concurrency" "$test_duration")
        
        # 提取关键指标
        local summary=$(awk -F',' '
        BEGIN { min_start_time = 0; max_end_time = 0 }
        NR>1 {
            total++
            if (min_start_time == 0 || $1 < min_start_time) min_start_time = $1
            if ($2 > max_end_time) max_end_time = $2
            
            if ($4 == 200) {
                successful++
                total_success_time += $3
                if ($3 > max_time) max_time = $3
            } else failed++
        }
        END {
            success_rate = (total > 0) ? (successful / total * 100) : 0
            avg_time = (successful > 0) ? (total_success_time / successful) : 0
            duration = (max_end_time > min_start_time) ? (max_end_time - min_start_time) : 1
            qps = (duration > 0) ? (total / duration) : 0
            printf "%d,%d,%d,%.2f,%.3f,%.3f,%.2f", 
                   total, (successful?successful:0), (failed?failed:0), 
                   success_rate, avg_time, (max_time?max_time:0), qps
        }' "$result_file")
        
        echo "$concurrency,$summary" >> "$batch_summary"
        
        # 等待系统恢复
        log "等待系统恢复..."
        sleep 60
    done
    
    log "批量测试完成，摘要文件: $batch_summary"
    echo "$batch_summary"
}

# 压力测试（逐步增加并发）
stress_test() {
    local max_concurrency=${1:-100}
    local step=${2:-5}
    local duration_per_step=${3:-60}
    
    log "开始压力测试: 最大并发=$max_concurrency, 步长=$step"
    
    local stress_result="$OUTPUT_DIR/stress_test_$(date +%Y%m%d_%H%M%S).csv"
    echo "concurrency,timestamp,qps,avg_response_time,error_rate" > "$stress_result"
    
    for ((concurrency=step; concurrency<=max_concurrency; concurrency+=step)); do
        log "压力测试: $concurrency 并发"
        
        local test_start=$(date +%s)
        local temp_result="/tmp/stress_temp_$concurrency.csv"
        echo "start_time,end_time,duration,response_code,error_msg" > "$temp_result"
        
        # 运行测试
        local end_time=$((test_start + duration_per_step))
        while [ $(date +%s) -lt $end_time ]; do
            for ((i=1; i<=concurrency; i++)); do
                single_request >> "$temp_result" &
            done
            wait
            sleep 1
        done
        
        # 分析结果
        local analysis=$(awk -F',' '
        NR>1 {
            total++
            if ($4 == 200) successful++
            else failed++
            total_time += $3
        }
        END {
            error_rate = (total > 0) ? (failed / total * 100) : 0
            avg_time = (successful > 0) ? (total_time / successful) : 0
            qps = total / '$duration_per_step'
            printf "%.2f,%.3f,%.2f", qps, avg_time, error_rate
        }' "$temp_result")
        
        echo "$concurrency,$(date '+%Y-%m-%d %H:%M:%S'),$analysis" >> "$stress_result"
        
        # 清理临时文件
        rm -f "$temp_result"
        
        # 检查错误率，如果过高则停止
        local error_rate=$(echo "$analysis" | cut -d',' -f3)
        if (( $(echo "$error_rate > 50" | bc -l) )); then
            log "错误率过高 ($error_rate%)，停止压力测试"
            break
        fi
    done
    
    log "压力测试完成: $stress_result"
    echo "$stress_result"
}

# 主函数
main() {
    case "${1:-single}" in
        "single")
            local concurrency=${2:-10}
            local duration=${3:-120}
            concurrent_test "$concurrency" "$duration"
            ;;
        "batch")
            local duration=${2:-120}
            batch_test "$duration"
            ;;
        "stress")
            local max_concurrency=${2:-100}
            local step=${3:-5}
            local duration=${4:-60}
            stress_test "$max_concurrency" "$step" "$duration"
            ;;
        *)
            echo "用法: $0 {single|batch|stress} [参数...]"
            echo ""
            echo "命令说明:"
            echo "  single [并发数] [持续时间]                    - 单个并发量测试"
            echo "  batch [单次持续时间]                          - 批量测试多个并发量"
            echo "  stress [最大并发] [步长] [每步持续时间]        - 压力测试"
            echo ""
            echo "例子:"
            echo "  $0 single 20 180        # 20并发测试180秒"
            echo "  $0 batch 120            # 批量测试，每个并发量120秒"
            echo "  $0 stress 100 10 60     # 压力测试到100并发，步长10，每步60秒"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"