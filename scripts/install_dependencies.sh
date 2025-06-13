 #!/bin/bash

# 安装测试依赖脚本
# 作者: AI Assistant
# 用途: 安装性能测试所需的依赖包

set -e

echo "=== 安装 Trustee 性能测试依赖 ==="
echo "开始时间: $(date)"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本"
    exit 1
fi

# 更新包管理器
echo "1. 更新系统包管理器..."
echo "----------------------------------------"
if command -v yum &> /dev/null; then
    yum update -y >/dev/null 2>&1 || echo "警告: yum update 失败，继续安装"
elif command -v apt &> /dev/null; then
    apt update -y >/dev/null 2>&1 || echo "警告: apt update 失败，继续安装"
fi

# 安装系统工具
echo "2. 安装系统监控工具..."
echo "----------------------------------------"
install_packages=(
    "htop"
    "sysstat"      # iostat, sar
    "psmisc"       # pstree, killall
    "procps-ng"    # ps, top
    "net-tools"    # netstat
    "iproute"      # ss
    "curl"
    "wget"
    "bc"           # 计算器
    "parallel"     # GNU parallel
)

for package in "${install_packages[@]}"; do
    echo "正在安装 $package..."
    if command -v yum &> /dev/null; then
        yum install -y "$package" >/dev/null 2>&1 || echo "警告: $package 安装失败"
    elif command -v apt &> /dev/null; then
        apt install -y "$package" >/dev/null 2>&1 || echo "警告: $package 安装失败"
    fi
done

# 安装 Python 3 和 pip
echo "3. 安装 Python 环境..."
echo "----------------------------------------"
if ! command -v python3 &> /dev/null; then
    echo "安装 Python 3..."
    if command -v yum &> /dev/null; then
        yum install -y python3 python3-pip >/dev/null 2>&1
    elif command -v apt &> /dev/null; then
        apt install -y python3 python3-pip >/dev/null 2>&1
    fi
fi

# 检查 Python 版本
python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
echo "✓ Python 版本: $python_version"

# 安装 Python 依赖包
echo "4. 安装 Python 依赖包..."
echo "----------------------------------------"
python_packages=(
    "matplotlib>=3.5.0"
    "plotly>=5.0.0"
    "pandas>=1.3.0"
    "numpy>=1.21.0"
    "psutil>=5.8.0"
    "jinja2>=3.0.0"
    "kaleido"          # plotly 导出图片
    "requests>=2.25.0"
)

for package in "${python_packages[@]}"; do
    echo "正在安装 Python 包: $package"
    pip3 install "$package" --quiet || echo "警告: $package 安装失败"
done

# 创建 Python 虚拟环境（可选）
echo "5. 创建 Python 虚拟环境（可选）..."
echo "----------------------------------------"
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "✓ 虚拟环境已创建在 venv/ 目录"
    echo "使用命令激活: source venv/bin/activate"
else
    echo "✓ 虚拟环境已存在"
fi

# 验证安装
echo "6. 验证安装结果..."
echo "----------------------------------------"

# 检查系统工具
tools_to_check=("htop" "iostat" "curl" "python3" "pip3")
failed_tools=0

for tool in "${tools_to_check[@]}"; do
    if command -v "$tool" &> /dev/null; then
        echo "✓ $tool 可用"
    else
        echo "✗ $tool 不可用"
        ((failed_tools++))
    fi
done

# 检查 Python 包
echo ""
echo "Python 包检查:"
python3 -c "
import sys
packages = ['matplotlib', 'plotly', 'pandas', 'numpy', 'psutil', 'jinja2', 'requests']
failed = 0
for pkg in packages:
    try:
        __import__(pkg)
        print(f'✓ {pkg} 可用')
    except ImportError:
        print(f'✗ {pkg} 不可用')
        failed += 1
        
if failed == 0:
    print('\n所有 Python 包安装成功')
    sys.exit(0)
else:
    print(f'\n{failed} 个 Python 包安装失败')
    sys.exit(1)
"

python_status=$?

# 检查并创建测试配置文件
echo "7. 检查配置文件..."
echo "----------------------------------------"

# 获取项目根目录路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

CONFIG_FILE="$PROJECT_ROOT/config/test_config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "配置文件不存在，正在创建..."
    mkdir -p "$PROJECT_ROOT/config"
    
    cat > "$CONFIG_FILE" << 'EOF'
{
    "processes": [
        "kbs",
        "grpc-as", 
        "rvps",
        "trustee-gateway"
    ],
    "test_url": "http://127.0.0.1:8081/api",
    "test_command": "kbs-client --url http://127.0.0.1:8081/api attest",
    "concurrency_levels": [5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100],
    "test_duration": {
        "warmup": 30,
        "steady": 120,
        "cooldown": 30
    },
    "monitoring": {
        "interval": 1,
        "metrics": ["cpu", "memory", "network", "disk"]
    },
    "thresholds": {
        "cpu_warning": 80,
        "cpu_critical": 90,
        "memory_warning": 80,
        "memory_critical": 90
    }
}
EOF
    echo "✓ 配置文件已创建: $CONFIG_FILE"
else
    echo "✓ 配置文件已存在: $CONFIG_FILE"
fi

# 总结
echo ""
echo "=== 安装完成总结 ==="
if [ $failed_tools -eq 0 ] && [ $python_status -eq 0 ]; then
    echo "✓ 所有依赖安装成功"
    echo ""
    echo "下一步操作:"
    echo "1. 运行服务检查: ./scripts/check_services.sh"
    echo "2. 执行性能测试: ./scripts/run_performance_test.sh"
    exit 0
else
    echo "✗ 部分依赖安装失败，请检查错误信息"
    exit 1
fi