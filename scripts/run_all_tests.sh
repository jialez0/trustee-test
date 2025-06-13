#!/bin/bash

# Trustee Service 性能测试主执行脚本
# 作者: AI Assistant
# 用途: 一键执行完整的性能测试流程

set -e

# 脚本信息
SCRIPT_NAME="Trustee Service 性能测试"
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 打印带颜色的信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}$1${NC}"
}

# 显示欢迎信息
show_banner() {
    clear
    print_header "════════════════════════════════════════════════════════════════"
    print_header "  🔒 $SCRIPT_NAME v$SCRIPT_VERSION"
    print_header "════════════════════════════════════════════════════════════════"
    echo ""
    print_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    print_info "执行用户: $(whoami)"
    print_info "工作目录: $PROJECT_ROOT"
    echo ""
}

# 检查运行环境
check_environment() {
    print_header "🔍 环境检查阶段"
    echo ""
    
    # 检查是否为 root 用户
    if [ "$EUID" -ne 0 ]; then
        print_warning "建议使用 root 权限运行以获得完整的系统监控权限"
    fi
    
    # 检查脚本权限
    local scripts_to_check=(
        "scripts/check_services.sh"
        "scripts/install_dependencies.sh"
        "scripts/monitor_resources.sh"
        "scripts/concurrent_test.sh"
        "scripts/run_performance_test.sh"
        "scripts/generate_report.py"
    )
    
    for script in "${scripts_to_check[@]}"; do
        if [ -f "$PROJECT_ROOT/$script" ]; then
            chmod +x "$PROJECT_ROOT/$script"
            print_info "✓ $script 权限已设置"
        else
            print_error "✗ 缺少脚本文件: $script"
            return 1
        fi
    done
    
    print_success "环境检查通过"
    echo ""
}

# 安装依赖
install_dependencies() {
    print_header "📦 依赖安装阶段"
    echo ""
    
    cd "$PROJECT_ROOT"
    
    if [ ! -f ".dependencies_installed" ]; then
        print_info "正在安装测试依赖..."
        if "$SCRIPT_DIR/install_dependencies.sh"; then
            touch .dependencies_installed
            print_success "依赖安装完成"
        else
            print_error "依赖安装失败"
            return 1
        fi
    else
        print_info "依赖已安装，跳过安装步骤"
    fi
    
    echo ""
}

# 检查服务状态
check_services() {
    print_header "🔧 服务状态检查"
    echo ""
    
    cd "$PROJECT_ROOT"
    
    print_info "检查 Trustee 服务状态..."
    if "$SCRIPT_DIR/check_services.sh"; then
        print_success "服务状态正常"
    else
        print_error "服务状态异常，请确保所有 Trustee 服务正在运行"
        echo ""
        print_info "请检查以下服务:"
        print_info "  - kbs (Key Broker Service)"
        print_info "  - grpc-as (gRPC Authentication Service)"
        print_info "  - rvps (Remote Verification Policy Service)"
        print_info "  - trustee-gateway (Gateway Service)"
        print_info "  - as-restful (RESTful Authentication Service)"
        echo ""
        read -p "是否继续执行测试？[y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "测试已取消"
            exit 1
        fi
    fi
    
    echo ""
}

# 显示测试配置
show_test_configuration() {
    print_header "⚙️  测试配置信息"
    echo ""
    
    local config_file="$PROJECT_ROOT/config/test_config.json"
    if [ -f "$config_file" ]; then
        print_info "配置文件: $config_file"
        print_info "并发量级别: $(jq -r '.concurrency_levels | join(", ")' "$config_file" 2>/dev/null || echo "5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100")"
        print_info "单次测试时长: $(jq -r '.test_duration.steady_state_seconds' "$config_file" 2>/dev/null || echo "120")秒"
        print_info "预热时间: $(jq -r '.test_duration.warmup_seconds' "$config_file" 2>/dev/null || echo "30")秒"
        print_info "冷却时间: $(jq -r '.test_duration.cooldown_seconds' "$config_file" 2>/dev/null || echo "30")秒"
    else
        print_warning "配置文件不存在，使用默认配置"
        print_info "并发量级别: 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100"
        print_info "单次测试时长: 120秒"
        print_info "预热时间: 30秒"
        print_info "冷却时间: 30秒"
    fi
    
    print_info "预计总测试时间: 约45分钟"
    echo ""
}

# 执行性能测试
run_performance_test() {
    print_header "🚀 性能测试执行阶段"
    echo ""
    
    cd "$PROJECT_ROOT"
    
    print_info "开始执行性能测试..."
    echo ""
    
    # 创建测试会话日志
    local session_log="results/logs/test_session_$(date +%Y%m%d_%H%M%S).log"
    mkdir -p "$(dirname "$session_log")"
    
    # 执行测试并记录日志
    if "$SCRIPT_DIR/run_performance_test.sh" 2>&1 | tee "$session_log"; then
        print_success "性能测试执行完成"
    else
        print_error "性能测试执行失败"
        print_info "详细日志: $session_log"
        return 1
    fi
    
    echo ""
}

# 显示测试结果
show_results() {
    print_header "📊 测试结果"
    echo ""
    
    local results_dir="$PROJECT_ROOT/results"
    
    if [ -d "$results_dir" ]; then
        print_info "测试结果目录: $results_dir"
        echo ""
        
        # 显示主要输出文件
        print_info "主要输出文件:"
        
        # 查找最新的报告文件
        local latest_html_report=$(find "$results_dir/reports" -name "*.html" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        local latest_archive=$(find "$results_dir/archives" -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        
        if [ -n "$latest_html_report" ]; then
            print_info "  📄 HTML报告: $latest_html_report"
        fi
        
        if [ -n "$latest_archive" ]; then
            print_info "  📦 测试归档: $latest_archive"
        fi
        
        # 显示系统信息文件
        if [ -f "$results_dir/system_info.txt" ]; then
            print_info "  💻 系统信息: $results_dir/system_info.txt"
        fi
        
        # 显示数据文件数量
        local data_files=$(find "$results_dir/raw_data" -name "*.csv" -type f 2>/dev/null | wc -l)
        print_info "  📈 数据文件: $data_files 个 CSV 文件"
        
        echo ""
        
        # 快捷操作提示
        print_info "快捷操作:"
        if [ -n "$latest_html_report" ]; then
            print_info "  查看报告: firefox '$latest_html_report'"
        fi
        print_info "  查看数据: ls -la '$results_dir/raw_data/'"
        print_info "  查看日志: ls -la '$results_dir/logs/'"
        
    else
        print_warning "未找到测试结果目录"
    fi
    
    echo ""
}

# 清理函数
cleanup() {
    print_info "清理测试环境..."
    
    # 停止可能仍在运行的后台进程
    pkill -f "monitor_resources.sh" 2>/dev/null || true
    pkill -f "concurrent_test.sh" 2>/dev/null || true
    pkill -f "kbs-client" 2>/dev/null || true
    
    print_info "清理完成"
}

# 错误处理
handle_error() {
    local exit_code=$?
    local line_number=$1
    
    print_error "脚本在第 $line_number 行发生错误 (退出码: $exit_code)"
    cleanup
    exit $exit_code
}

# 设置错误处理
trap 'handle_error $LINENO' ERR
trap 'cleanup' EXIT

# 显示使用帮助
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help              显示此帮助信息"
    echo "  --dry-run              只检查环境，不执行测试"
    echo "  --skip-deps            跳过依赖安装"
    echo "  --skip-service-check   跳过服务状态检查"
    echo "  --quick                快速测试模式（较少并发量）"
    echo ""
    echo "示例:"
    echo "  $0                     # 执行完整测试"
    echo "  $0 --dry-run           # 仅检查环境"
    echo "  $0 --skip-deps         # 跳过依赖安装"
    echo "  $0 --quick             # 快速测试"
    echo ""
}

# 主执行函数
main() {
    local skip_deps=false
    local skip_service_check=false
    local dry_run=false
    local quick_mode=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --skip-deps)
                skip_deps=true
                shift
                ;;
            --skip-service-check)
                skip_service_check=true
                shift
                ;;
            --quick)
                quick_mode=true
                shift
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 显示欢迎界面
    show_banner
    
    # 执行测试流程
    check_environment
    
    if [ "$skip_deps" = false ]; then
        install_dependencies
    else
        print_info "跳过依赖安装"
    fi
    
    if [ "$skip_service_check" = false ]; then
        check_services
    else
        print_info "跳过服务状态检查"
    fi
    
    show_test_configuration
    
    if [ "$dry_run" = true ]; then
        print_info "干运行模式，测试环境检查完成"
        exit 0
    fi
    
    # 确认开始测试
    print_warning "即将开始性能测试，此过程可能需要45分钟"
    read -p "是否继续？[Y/n] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_info "测试已取消"
        exit 0
    fi
    
    # 执行测试
    run_performance_test
    
    # 显示结果
    show_results
    
    # 完成信息
    print_header "🎉 测试完成!"
    print_success "Trustee Service 性能测试已成功完成"
    print_info "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

# 执行主函数
main "$@" 