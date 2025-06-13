# Trustee Service 性能测试方案

## 1. 测试概述

### 1.1 测试目标
- 监控 trustee service 五个核心进程的资源占用情况
- 分析不同并发量（5-100）下的性能变化
- 为产品化部署提供资源规划依据

### 1.2 测试对象
- **kbs**: 密钥经纪服务
- **grpc-as**: gRPC 认证服务  
- **rvps**: 远程验证配置服务
- **trustee-gateway**: 网关服务
- **第五个进程**: (请确认具体进程名称)

### 1.3 测试指标
- **CPU 使用率**: 各进程 CPU 占用百分比
- **内存使用量**: RSS/VSZ 内存占用
- **响应时间**: 请求延迟统计
- **吞吐量**: QPS (每秒请求数)
- **错误率**: 失败请求占比

## 2. 测试环境

### 2.1 系统信息
- **操作系统**: Linux 5.10.134-18.al8.x86_64
- **测试命令**: `kbs-client --url http://127.0.0.1:8081/api attest`
- **监控对象**: trustee service 相关进程

### 2.2 测试工具
- **系统监控**: `top`, `htop`, `ps`, `iostat`
- **网络测试**: 自定义并发测试脚本
- **数据收集**: Python 脚本 + CSV 存储
- **报告生成**: Python + matplotlib/plotly

## 3. 测试设计

### 3.1 并发量设置
测试将覆盖以下并发量级别：
```
5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100
```

### 3.2 测试持续时间
- **预热阶段**: 30秒
- **稳定测试**: 120秒  
- **冷却阶段**: 30秒
- **单次测试总时长**: 180秒

### 3.3 数据采集频率
- **资源监控**: 每1秒采集一次
- **性能指标**: 每次请求记录

## 4. 测试执行步骤

### 4.1 环境准备
```bash
# 1. 检查 trustee 服务状态
./scripts/check_services.sh

# 2. 安装测试依赖
./scripts/install_dependencies.sh

# 3. 创建结果目录
mkdir -p results/{raw_data,reports,logs}
```

### 4.2 执行测试
```bash
# 运行完整测试套件
./scripts/run_performance_test.sh

# 或分步执行
./scripts/monitor_resources.sh &  # 后台启动资源监控
./scripts/concurrent_test.sh 10   # 执行10并发测试
```

### 4.3 生成报告
```bash
# 生成性能分析报告
python3 scripts/generate_report.py

# 查看报告
firefox results/reports/trustee_performance_report.html
```

## 5. 预期输出

### 5.1 数据文件
- `results/raw_data/resource_usage_*.csv`: 资源使用数据
- `results/raw_data/performance_metrics_*.csv`: 性能指标数据
- `results/logs/test_execution.log`: 测试执行日志

### 5.2 报告文件
- `results/reports/trustee_performance_report.html`: HTML 交互式报告
- `results/reports/trustee_performance_report.pdf`: PDF 版本报告
- `results/reports/charts/`: 图表文件目录

### 5.3 关键图表
1. **CPU 使用率随并发量变化趋势图**
2. **内存使用量随并发量变化趋势图**
3. **各进程资源占用对比图**
4. **响应时间分布直方图**
5. **QPS vs 并发量关系图**
6. **错误率随并发量变化图**

## 6. 风险控制

### 6.1 系统保护
- 设置资源使用上限告警（CPU > 90%, Memory > 80%）
- 异常情况自动停止测试
- 保留系统恢复脚本

### 6.2 数据完整性
- 每个测试点重复3次取平均值
- 数据异常检测和过滤
- 自动备份测试数据

## 7. 后续分析

### 7.1 性能基线
- 建立不同并发量下的性能基线
- 识别系统瓶颈点
- 制定资源配置建议

### 7.2 部署建议
- 最小资源配置要求
- 推荐生产环境配置
- 扩容策略建议

---

**执行命令**: `bash scripts/run_all_tests.sh`

**预计测试时长**: 约45分钟（13个并发量级别 × 3分钟/测试） 