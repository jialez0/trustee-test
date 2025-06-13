# 🔒 Trustee Service 性能测试方案

这是一个专业的 Trustee Service 性能测试工具包，用于监控和分析 trustee service 五个核心进程（kbs、grpc-as、rvps、trustee-gateway）在不同并发量下的资源占用情况。

## 📋 功能特性

- **全面监控**: CPU、内存、线程、文件描述符等系统资源
- **多并发测试**: 支持 5-100 并发量的自动化测试
- **专业报告**: 生成 HTML 交互式报告和图表
- **智能分析**: 自动分析性能瓶颈和资源使用趋势
- **安全防护**: 内置系统保护机制，防止测试过载
- **易于使用**: 一键执行，自动化程度高

## 🏗️ 目录结构

```
trustee-test/
├── README.md                          # 项目说明文档
├── trustee_performance_test_plan.md   # 详细测试方案
├── config/
│   └── test_config.json              # 测试配置文件
├── scripts/
│   ├── run_all_tests.sh              # 主执行脚本（推荐）
│   ├── check_services.sh             # 服务状态检查
│   ├── install_dependencies.sh       # 依赖安装
│   ├── monitor_resources.sh          # 资源监控
│   ├── concurrent_test.sh            # 并发测试
│   ├── run_performance_test.sh       # 性能测试主脚本
│   └── generate_report.py            # 报告生成
└── results/                          # 测试结果目录
    ├── raw_data/                     # 原始数据
    ├── reports/                      # 测试报告
    ├── charts/                       # 图表文件
    ├── logs/                         # 日志文件
    └── archives/                     # 归档文件
```

## 🚀 快速开始

### 1. 一键执行（推荐）

```bash
# 执行完整测试（约45分钟）
bash scripts/run_all_tests.sh

# 仅检查环境，不执行测试
bash scripts/run_all_tests.sh --dry-run

# 快速测试模式（较少并发量）
bash scripts/run_all_tests.sh --quick
```

### 2. 分步执行

```bash
# 1. 检查服务状态
./scripts/check_services.sh

# 2. 安装依赖
./scripts/install_dependencies.sh

# 3. 执行性能测试
./scripts/run_performance_test.sh

# 4. 生成报告
python3 scripts/generate_report.py \
  --test-name "my_test" \
  --data-dir "results/raw_data" \
  --output-dir "results/reports"
```

## 📊 测试配置

### 默认测试参数

- **并发量级别**: 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100
- **单次测试时长**: 120秒
- **预热时间**: 30秒
- **冷却时间**: 30秒
- **监控频率**: 每秒1次
- **测试命令**: `kbs-client --url http://127.0.0.1:8081/api attest`

### 自定义配置

编辑 `config/test_config.json` 文件来自定义测试参数：

```json
{
    "concurrency_levels": [5, 10, 20, 50, 100],
    "test_duration": {
        "steady_state_seconds": 60,
        "warmup_seconds": 15,
        "cooldown_seconds": 15
    },
    "thresholds": {
        "cpu_warning_percent": 80,
        "memory_warning_percent": 80
    }
}
```

## 🔧 系统要求

### 操作系统
- Linux (已测试: CentOS 8, Ubuntu 18.04+)
- Root 权限（推荐，用于完整系统监控）

### 软件依赖
- **系统工具**: htop, sysstat, psmisc, curl, bc
- **Python 3.7+** 及以下包:
  - matplotlib >= 3.5.0
  - plotly >= 5.0.0
  - pandas >= 1.3.0
  - numpy >= 1.21.0
  - psutil >= 5.8.0

### Trustee 服务
确保以下服务正在运行：
- kbs (Key Broker Service)
- grpc-as (gRPC Authentication Service)
- rvps (Remote Verification Policy Service)
- trustee-gateway (Gateway Service)

## 📈 测试输出

### 1. 数据文件
- `resource_usage_*.csv`: 资源使用数据
- `concurrent_test_*.csv`: 并发测试结果
- `concurrent_stats_*.csv`: 性能统计数据

### 2. 报告文件
- `*_report.html`: 交互式 HTML 报告
- `system_info.txt`: 系统信息摘要

### 3. 关键图表
1. **CPU 使用率随并发量变化趋势图**
2. **内存使用量随并发量变化趋势图**
3. **各进程资源占用对比图**
4. **响应时间分布图**
5. **QPS vs 并发量关系图**
6. **成功率随并发量变化图**

## 🎯 典型使用场景

### 场景1: 产品部署前的性能评估
```bash
# 执行完整测试，获得详细的性能基线
bash scripts/run_all_tests.sh
```

### 场景2: 快速性能检查
```bash
# 快速验证服务性能，耗时约15分钟
bash scripts/run_all_tests.sh --quick
```

### 场景3: 持续集成中的性能回归测试
```bash
# 在CI/CD中集成性能测试
bash scripts/run_all_tests.sh --skip-deps --dry-run
if [ $? -eq 0 ]; then
    bash scripts/run_all_tests.sh --skip-deps
fi
```

### 场景4: 单独测试特定并发量
```bash
# 测试特定并发量（如50并发）
./scripts/concurrent_test.sh single 50 180
./scripts/monitor_resources.sh monitor test_50c 180 &
wait
```

## 📊 报告解读

### 性能指标说明

1. **CPU 使用率**: 各进程的 CPU 占用百分比
2. **内存使用量**: RSS (实际物理内存) 和 VSZ (虚拟内存) 
3. **QPS (每秒请求数)**: 系统处理请求的吞吐能力
4. **响应时间**: 请求处理延迟（平均值、P95、P99）
5. **成功率**: 成功请求占总请求的百分比

### 部署建议参考

报告会根据测试结果自动生成部署建议：

- **最小 CPU 配置**: 基于峰值 CPU 使用量 + 50% 缓冲
- **推荐内存配置**: 基于峰值内存使用量 + 50% 缓冲  
- **最佳并发量**: 基于 95% 成功率的最大并发数
- **扩容阈值**: 建议的资源使用率告警线

## 🔧 故障排除

### 常见问题

1. **服务检查失败**
   ```bash
   # 检查服务状态
   ps aux | grep -E "(kbs|grpc-as|rvps|trustee-gateway)"
   
   # 检查端口监听
   ss -tuln | grep -E "(8080|8081)"
   ```

2. **kbs-client 命令不可用**
   ```bash
   # 检查 kbs-client 安装
   which kbs-client
   
   # 测试连接
   kbs-client --url http://127.0.0.1:8081/api --help
   ```

3. **Python 依赖问题**
   ```bash
   # 重新安装 Python 依赖
   pip3 install -r requirements.txt
   
   # 或使用虚拟环境
   python3 -m venv venv
   source venv/bin/activate
   pip install matplotlib plotly pandas psutil
   ```

4. **权限问题**
   ```bash
   # 设置脚本执行权限
   chmod +x scripts/*.sh
   
   # 使用 root 权限运行
   sudo bash scripts/run_all_tests.sh
   ```

### 日志分析

查看详细日志来诊断问题：

```bash
# 查看主测试日志
tail -f results/logs/main_test.log

# 查看资源监控日志
tail -f results/logs/resource_monitor.log

# 查看并发测试日志
tail -f results/logs/concurrent_test.log
```

## 🤝 贡献指南

欢迎提交问题和改进建议！

### 贡献方式
1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 📞 支持

如有问题或建议，请：
1. 查看本文档的故障排除章节
2. 提交 GitHub Issue
3. 联系项目维护者

---

**注意**: 这是专为 Trustee Service 产品化部署设计的性能测试工具。测试过程中会对系统产生一定负载，请在非生产环境中运行。 