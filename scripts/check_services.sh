#!/bin/bash

# trustee 服务状态检查脚本
# 作者: AI Assistant
# 用途: 检查 trustee service 相关进程是否正常运行

set -e

echo "=== Trustee Service 状态检查 ==="
echo "检查时间: $(date)"
echo ""

# 定义需要检查的进程
PROCESSES=("kbs" "grpc-as" "rvps" "trustee-gateway")

# 检查进程是否运行
check_process() {
    local process_name=$1
    local pid=$(pgrep -f "$process_name" 2>/dev/null || echo "")
    
    if [ -n "$pid" ]; then
        echo "✓ $process_name 正在运行 (PID: $pid)"
        # 显示进程详细信息
        ps -p $pid -o pid,ppid,cmd,pcpu,pmem --no-headers | head -1
        return 0
    else
        echo "✗ $process_name 未运行"
        return 1
    fi
}

# 检查端口是否监听
check_port() {
    local port=$1
    local desc=$2
    
    if ss -tuln | grep -q ":$port "; then
        echo "✓ 端口 $port ($desc) 正在监听"
        return 0
    else
        echo "✗ 端口 $port ($desc) 未监听"
        return 1
    fi
}

# 检查所有进程
echo "1. 进程状态检查:"
echo "----------------------------------------"
failed_processes=0
for process in "${PROCESSES[@]}"; do
    if ! check_process "$process"; then
        ((failed_processes++))
    fi
    echo ""
done

echo "2. 端口监听检查:"
echo "----------------------------------------"
# 检查关键端口 (根据实际配置修改)
check_port "8081" "KBS API"
check_port "8080" "Gateway"
echo ""

# 检查 kbs-client 命令可用性
echo "3. 客户端工具检查:"
echo "----------------------------------------"
if command -v kbs-client &> /dev/null; then
    echo "✓ kbs-client 命令可用"
    echo "版本信息: $(kbs-client --version 2>/dev/null || echo '无法获取版本信息')"
else
    echo "✗ kbs-client 命令不可用"
    echo "请确保 kbs-client 已安装并在 PATH 中"
    ((failed_processes++))
fi
echo ""

# 测试连接
echo "4. 连接测试:"
echo "----------------------------------------"
if timeout 5 bash -c "curl -s http://127.0.0.1:8081/api/health" &>/dev/null || \
   timeout 5 bash -c "kbs-client --url http://127.0.0.1:8081/api --help" &>/dev/null; then
    echo "✓ 服务连接正常"
else
    echo "✗ 服务连接失败"
    echo "请检查服务是否正确启动"
    ((failed_processes++))
fi
echo ""

# 系统资源检查
echo "5. 系统资源状态:"
echo "----------------------------------------"
echo "CPU 使用率: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
echo "内存使用率: $(free | grep Mem | awk '{printf("%.1f%%\n", $3/$2 * 100)}')"
echo "磁盘使用率: $(df -h / | awk 'NR==2 {print $5}')"
echo ""

# 总结
echo "=== 检查结果总结 ==="
if [ $failed_processes -eq 0 ]; then
    echo "✓ 所有检查项目通过，系统准备就绪"
    exit 0
else
    echo "✗ 发现 $failed_processes 个问题，请修复后重试"
    exit 1
fi 