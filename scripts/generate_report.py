 #!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Trustee Service 性能测试报告生成器
作者: AI Assistant
用途: 分析测试数据并生成可视化报告
"""

import os
import sys
import argparse
import glob
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import plotly.graph_objects as go
import plotly.express as px
from plotly.subplots import make_subplots
import plotly.offline as pyo
from datetime import datetime
import json
import logging

# 设置中文字体和样式
plt.rcParams['font.sans-serif'] = ['SimHei', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False
plt.style.use('seaborn-v0_8')

class TrusteeReportGenerator:
    def __init__(self, test_name, data_dir, output_dir):
        self.test_name = test_name
        self.data_dir = data_dir
        self.output_dir = output_dir
        self.charts_dir = os.path.join(output_dir, 'charts')
        
        # 创建输出目录
        os.makedirs(output_dir, exist_ok=True)
        os.makedirs(self.charts_dir, exist_ok=True)
        
        # 配置日志
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger(__name__)
        
        # 初始化数据容器
        self.resource_data = {}
        self.performance_data = {}
        self.summary_stats = {}
    
    def load_data(self):
        """加载所有测试数据"""
        self.logger.info("开始加载测试数据...")
        
        # 加载资源使用数据
        resource_files = glob.glob(os.path.join(self.data_dir, 'resource_usage_*.csv'))
        self.logger.info(f"找到 {len(resource_files)} 个资源监控文件")
        
        for file_path in resource_files:
            try:
                # 从文件名提取并发量信息
                filename = os.path.basename(file_path)
                if '_' in filename:
                    parts = filename.split('_')
                    concurrency = None
                    for part in parts:
                        if part.endswith('c.csv'):
                            concurrency = int(part[:-5])
                            break
                    
                    if concurrency:
                        df = pd.read_csv(file_path)
                        df['timestamp'] = pd.to_datetime(df['timestamp'])
                        self.resource_data[concurrency] = df
                        self.logger.info(f"加载 {concurrency} 并发资源数据: {len(df)} 条记录")
            except Exception as e:
                self.logger.error(f"加载资源文件失败 {file_path}: {e}")
        
        # 加载性能测试数据
        perf_files = glob.glob(os.path.join(self.data_dir, 'concurrent_test_*.csv'))
        self.logger.info(f"找到 {len(perf_files)} 个性能测试文件")
        
        for file_path in perf_files:
            try:
                # 从文件名提取并发量信息
                filename = os.path.basename(file_path)
                parts = filename.split('_')
                if len(parts) >= 3:
                    concurrency = int(parts[2])
                    df = pd.read_csv(file_path)
                    self.performance_data[concurrency] = df
                    self.logger.info(f"加载 {concurrency} 并发性能数据: {len(df)} 条记录")
            except Exception as e:
                self.logger.error(f"加载性能文件失败 {file_path}: {e}")
        
        self.logger.info("数据加载完成")
    
    def analyze_resource_usage(self):
        """分析资源使用情况"""
        self.logger.info("开始分析资源使用情况...")
        
        self.summary_stats = {}
        
        for concurrency, df in self.resource_data.items():
            if df.empty:
                continue
                
            # 过滤掉系统数据，只分析应用进程
            app_df = df[df['process'] != 'system'].copy()
            
            if app_df.empty:
                continue
            
            stats = {
                'concurrency': concurrency,
                'processes': {},
                'total_cpu_avg': 0,
                'total_memory_avg': 0,
                'total_cpu_max': 0,
                'total_memory_max': 0
            }
            
            # 按进程分析
            for process in app_df['process'].unique():
                process_df = app_df[app_df['process'] == process]
                
                process_stats = {
                    'cpu_avg': process_df['cpu_percent'].mean(),
                    'cpu_max': process_df['cpu_percent'].max(),
                    'cpu_min': process_df['cpu_percent'].min(),
                    'memory_avg': process_df['memory_rss_mb'].mean(),
                    'memory_max': process_df['memory_rss_mb'].max(),
                    'memory_min': process_df['memory_rss_mb'].min(),
                    'threads_avg': process_df['threads'].mean(),
                    'fds_avg': process_df['fds'].mean(),
                    'sample_count': len(process_df)
                }
                
                stats['processes'][process] = process_stats
                stats['total_cpu_avg'] += process_stats['cpu_avg']
                stats['total_memory_avg'] += process_stats['memory_avg']
                stats['total_cpu_max'] += process_stats['cpu_max']
                stats['total_memory_max'] += process_stats['memory_max']
            
            self.summary_stats[concurrency] = stats
        
        self.logger.info("资源分析完成")
    
    def analyze_performance_metrics(self):
        """分析性能指标"""
        self.logger.info("开始分析性能指标...")
        
        for concurrency, df in self.performance_data.items():
            if df.empty:
                continue
            
            # 计算性能指标
            total_requests = len(df)
            successful_requests = len(df[df['response_code'] == 200])
            failed_requests = total_requests - successful_requests
            success_rate = (successful_requests / total_requests * 100) if total_requests > 0 else 0
            
            # 只计算成功请求的响应时间
            success_df = df[df['response_code'] == 200]
            if not success_df.empty:
                avg_response_time = success_df['duration'].mean()
                min_response_time = success_df['duration'].min()
                max_response_time = success_df['duration'].max()
                p95_response_time = success_df['duration'].quantile(0.95)
                p99_response_time = success_df['duration'].quantile(0.99)
            else:
                avg_response_time = min_response_time = max_response_time = 0
                p95_response_time = p99_response_time = 0
            
            # 计算 QPS
            if not df.empty:
                test_duration = df['end_time'].max() - df['start_time'].min()
                qps = total_requests / test_duration if test_duration > 0 else 0
            else:
                qps = 0
            
            # 更新汇总数据
            if concurrency in self.summary_stats:
                self.summary_stats[concurrency].update({
                    'total_requests': total_requests,
                    'successful_requests': successful_requests,
                    'failed_requests': failed_requests,
                    'success_rate': success_rate,
                    'avg_response_time': avg_response_time,
                    'min_response_time': min_response_time,
                    'max_response_time': max_response_time,
                    'p95_response_time': p95_response_time,
                    'p99_response_time': p99_response_time,
                    'qps': qps
                })
        
        self.logger.info("性能分析完成")
    
    def create_resource_charts(self):
        """创建资源使用图表"""
        self.logger.info("创建资源使用图表...")
        
        if not self.summary_stats:
            self.logger.warning("没有资源数据，跳过图表生成")
            return []
        
        charts = []
        
        # 1. CPU 使用率随并发量变化趋势图
        concurrencies = sorted(self.summary_stats.keys())
        total_cpu_avg = [self.summary_stats[c]['total_cpu_avg'] for c in concurrencies]
        total_cpu_max = [self.summary_stats[c]['total_cpu_max'] for c in concurrencies]
        
        fig = go.Figure()
        fig.add_trace(go.Scatter(
            x=concurrencies, y=total_cpu_avg,
            mode='lines+markers',
            name='平均 CPU 使用率',
            line=dict(color='#1f77b4', width=3)
        ))
        fig.add_trace(go.Scatter(
            x=concurrencies, y=total_cpu_max,
            mode='lines+markers',
            name='峰值 CPU 使用率',
            line=dict(color='#ff7f0e', width=3, dash='dash')
        ))
        
        fig.update_layout(
            title='CPU 使用率随并发量变化趋势',
            xaxis_title='并发量',
            yaxis_title='CPU 使用率 (%)',
            template='plotly_white',
            height=500
        )
        
        chart_file = os.path.join(self.charts_dir, 'cpu_usage_trend.html')
        fig.write_html(chart_file)
        charts.append(('CPU 使用率趋势', chart_file))
        
        # 2. 内存使用量随并发量变化趋势图
        total_memory_avg = [self.summary_stats[c]['total_memory_avg'] for c in concurrencies]
        total_memory_max = [self.summary_stats[c]['total_memory_max'] for c in concurrencies]
        
        fig = go.Figure()
        fig.add_trace(go.Scatter(
            x=concurrencies, y=total_memory_avg,
            mode='lines+markers',
            name='平均内存使用量',
            line=dict(color='#2ca02c', width=3)
        ))
        fig.add_trace(go.Scatter(
            x=concurrencies, y=total_memory_max,
            mode='lines+markers',
            name='峰值内存使用量',
            line=dict(color='#d62728', width=3, dash='dash')
        ))
        
        fig.update_layout(
            title='内存使用量随并发量变化趋势',
            xaxis_title='并发量',
            yaxis_title='内存使用量 (MB)',
            template='plotly_white',
            height=500
        )
        
        chart_file = os.path.join(self.charts_dir, 'memory_usage_trend.html')
        fig.write_html(chart_file)
        charts.append(('内存使用量趋势', chart_file))
        
        # 3. 各进程资源占用对比图（选择中等并发量）
        mid_concurrency = concurrencies[len(concurrencies)//2]
        processes = list(self.summary_stats[mid_concurrency]['processes'].keys())
        
        cpu_values = [self.summary_stats[mid_concurrency]['processes'][p]['cpu_avg'] for p in processes]
        memory_values = [self.summary_stats[mid_concurrency]['processes'][p]['memory_avg'] for p in processes]
        
        fig = make_subplots(
            rows=1, cols=2,
            subplot_titles=('CPU 使用率对比', '内存使用量对比'),
            specs=[[{"secondary_y": False}, {"secondary_y": False}]]
        )
        
        fig.add_trace(
            go.Bar(x=processes, y=cpu_values, name='CPU 使用率', marker_color='#1f77b4'),
            row=1, col=1
        )
        
        fig.add_trace(
            go.Bar(x=processes, y=memory_values, name='内存使用量', marker_color='#2ca02c'),
            row=1, col=2
        )
        
        fig.update_layout(
            title=f'各进程资源占用对比 ({mid_concurrency} 并发)',
            template='plotly_white',
            height=500
        )
        
        chart_file = os.path.join(self.charts_dir, 'process_resource_comparison.html')
        fig.write_html(chart_file)
        charts.append(('进程资源对比', chart_file))
        
        return charts
    
    def create_performance_charts(self):
        """创建性能图表"""
        self.logger.info("创建性能图表...")
        
        if not self.summary_stats:
            return []
        
        charts = []
        concurrencies = sorted(self.summary_stats.keys())
        
        # 4. QPS vs 并发量关系图
        qps_values = [self.summary_stats[c].get('qps', 0) for c in concurrencies]
        success_rates = [self.summary_stats[c].get('success_rate', 0) for c in concurrencies]
        
        fig = make_subplots(
            rows=1, cols=2,
            subplot_titles=('QPS 随并发量变化', '成功率随并发量变化'),
            specs=[[{"secondary_y": False}, {"secondary_y": False}]]
        )
        
        fig.add_trace(
            go.Scatter(x=concurrencies, y=qps_values, mode='lines+markers', 
                      name='QPS', line=dict(color='#9467bd', width=3)),
            row=1, col=1
        )
        
        fig.add_trace(
            go.Scatter(x=concurrencies, y=success_rates, mode='lines+markers',
                      name='成功率', line=dict(color='#17becf', width=3)),
            row=1, col=2
        )
        
        fig.update_layout(
            title='性能指标随并发量变化',
            template='plotly_white',
            height=500
        )
        
        chart_file = os.path.join(self.charts_dir, 'performance_metrics.html')
        fig.write_html(chart_file)
        charts.append(('性能指标', chart_file))
        
        # 5. 响应时间分布图
        avg_times = [self.summary_stats[c].get('avg_response_time', 0) for c in concurrencies]
        p95_times = [self.summary_stats[c].get('p95_response_time', 0) for c in concurrencies]
        p99_times = [self.summary_stats[c].get('p99_response_time', 0) for c in concurrencies]
        
        fig = go.Figure()
        fig.add_trace(go.Scatter(
            x=concurrencies, y=avg_times,
            mode='lines+markers',
            name='平均响应时间',
            line=dict(color='#8c564b', width=3)
        ))
        fig.add_trace(go.Scatter(
            x=concurrencies, y=p95_times,
            mode='lines+markers',
            name='P95 响应时间',
            line=dict(color='#e377c2', width=3)
        ))
        fig.add_trace(go.Scatter(
            x=concurrencies, y=p99_times,
            mode='lines+markers',
            name='P99 响应时间',
            line=dict(color='#7f7f7f', width=3)
        ))
        
        fig.update_layout(
            title='响应时间分布',
            xaxis_title='并发量',
            yaxis_title='响应时间 (秒)',
            template='plotly_white',
            height=500
        )
        
        chart_file = os.path.join(self.charts_dir, 'response_time_distribution.html')
        fig.write_html(chart_file)
        charts.append(('响应时间分布', chart_file))
        
        return charts
    
    def generate_html_report(self, resource_charts, performance_charts):
        """生成 HTML 报告"""
        self.logger.info("生成 HTML 报告...")
        
        # 准备数据表格
        table_data = []
        for concurrency in sorted(self.summary_stats.keys()):
            stats = self.summary_stats[concurrency]
            table_data.append({
                '并发量': concurrency,
                '总CPU(%)': f"{stats.get('total_cpu_avg', 0):.2f}",
                '总内存(MB)': f"{stats.get('total_memory_avg', 0):.2f}",
                '成功率(%)': f"{stats.get('success_rate', 0):.2f}",
                '平均响应时间(s)': f"{stats.get('avg_response_time', 0):.3f}",
                'QPS': f"{stats.get('qps', 0):.2f}"
            })
        
        # HTML 模板
        html_content = f"""
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Trustee Service 性能测试报告</title>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
    <style>
        body {{ font-family: 'Microsoft YaHei', Arial, sans-serif; margin: 20px; }}
        .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 30px; }}
        .summary {{ background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 30px; }}
        .chart-section {{ margin-bottom: 40px; }}
        .chart-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(800px, 1fr)); gap: 20px; }}
        .chart-container {{ background: white; border: 1px solid #dee2e6; border-radius: 8px; padding: 20px; }}
        table {{ width: 100%; border-collapse: collapse; margin-top: 20px; }}
        th, td {{ padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }}
        th {{ background-color: #f2f2f2; font-weight: bold; }}
        tr:hover {{ background-color: #f5f5f5; }}
        .metric {{ display: inline-block; margin: 10px 20px 10px 0; }}
        .metric-value {{ font-size: 24px; font-weight: bold; color: #007bff; }}
        .metric-label {{ color: #6c757d; font-size: 14px; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>🔒 Trustee Service 性能测试报告</h1>
        <p>测试名称: {self.test_name}</p>
        <p>生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
    </div>
    
    <div class="summary">
        <h2>📊 测试概要</h2>
        <div class="metric">
            <div class="metric-value">{len(self.summary_stats)}</div>
            <div class="metric-label">并发量级别</div>
        </div>
        <div class="metric">
            <div class="metric-value">{min(self.summary_stats.keys()) if self.summary_stats else 0}-{max(self.summary_stats.keys()) if self.summary_stats else 0}</div>
            <div class="metric-label">并发量范围</div>
        </div>
        <div class="metric">
            <div class="metric-value">{len(set().union(*[stats['processes'].keys() for stats in self.summary_stats.values()]))}</div>
            <div class="metric-label">监控进程数</div>
        </div>
    </div>
    
    <div class="chart-section">
        <h2>📈 资源使用情况</h2>
        <div class="chart-grid">
"""
        
        # 添加资源图表
        for chart_title, chart_file in resource_charts:
            with open(chart_file, 'r', encoding='utf-8') as f:
                chart_html = f.read()
                # 提取图表的 div 部分
                start = chart_html.find('<div id="') if '<div id="' in chart_html else chart_html.find('<div>')
                end = chart_html.rfind('</div>') + 6
                chart_content = chart_html[start:end] if start != -1 and end != -1 else chart_html
                
                html_content += f"""
            <div class="chart-container">
                <h3>{chart_title}</h3>
                {chart_content}
            </div>"""
        
        html_content += """
        </div>
    </div>
    
    <div class="chart-section">
        <h2>⚡ 性能指标</h2>
        <div class="chart-grid">
"""
        
        # 添加性能图表
        for chart_title, chart_file in performance_charts:
            with open(chart_file, 'r', encoding='utf-8') as f:
                chart_html = f.read()
                start = chart_html.find('<div id="') if '<div id="' in chart_html else chart_html.find('<div>')
                end = chart_html.rfind('</div>') + 6
                chart_content = chart_html[start:end] if start != -1 and end != -1 else chart_html
                
                html_content += f"""
            <div class="chart-container">
                <h3>{chart_title}</h3>
                {chart_content}
            </div>"""
        
        html_content += """
        </div>
    </div>
    
    <div class="summary">
        <h2>📋 详细数据表</h2>
        <table>
            <thead>
                <tr>
"""
        
        # 添加表头
        if table_data:
            for key in table_data[0].keys():
                html_content += f"<th>{key}</th>"
        
        html_content += """
                </tr>
            </thead>
            <tbody>
"""
        
        # 添加表格数据
        for row in table_data:
            html_content += "<tr>"
            for value in row.values():
                html_content += f"<td>{value}</td>"
            html_content += "</tr>"
        
        html_content += """
            </tbody>
        </table>
    </div>
    
    <div class="summary">
        <h2>💡 部署建议</h2>
        <h3>资源配置建议:</h3>
        <ul>
"""
        
        # 生成部署建议
        if self.summary_stats:
            max_cpu_percent = max(stats['total_cpu_avg'] for stats in self.summary_stats.values())
            max_memory = max(stats['total_memory_avg'] for stats in self.summary_stats.values())
            
            # CPU核心数计算：CPU使用率转换为核心数，并添加缓冲
            # 例如：4%使用率 = 0.04核心，加50%缓冲 = 0.06核心，但至少需要1个核心
            required_cpu_cores = max(1, int((max_cpu_percent / 100) * 1.5) + 1)
            
            html_content += f"""
            <li><strong>CPU:</strong> 建议配置至少 {required_cpu_cores} 个 CPU 核心（基于峰值使用量 {max_cpu_percent:.1f}% ≈ {max_cpu_percent/100:.2f} 核心 + 50% 缓冲 + 基础1核心）</li>
            <li><strong>内存:</strong> 建议配置至少 {int(max_memory * 1.5)} MB 内存（基于峰值使用量 {max_memory:.1f} MB + 50% 缓冲）</li>
            <li><strong>推荐并发量:</strong> 根据成功率和响应时间，建议生产环境并发量不超过 {max([c for c, s in self.summary_stats.items() if s.get('success_rate', 0) > 95], default=50)}</li>
"""
        
        html_content += """
        </ul>
    </div>
    
    <script>
        // 添加一些交互性
        document.addEventListener('DOMContentLoaded', function() {
            console.log('Trustee Performance Report Loaded');
        });
    </script>
</body>
</html>
"""
        
        # 保存 HTML 报告
        report_file = os.path.join(self.output_dir, f'{self.test_name}_report.html')
        with open(report_file, 'w', encoding='utf-8') as f:
            f.write(html_content)
        
        self.logger.info(f"HTML 报告已生成: {report_file}")
        return report_file
    
    def generate_report(self):
        """生成完整报告"""
        try:
            # 1. 加载数据
            self.load_data()
            
            # 2. 分析数据
            self.analyze_resource_usage()
            self.analyze_performance_metrics()
            
            # 3. 创建图表
            resource_charts = self.create_resource_charts()
            performance_charts = self.create_performance_charts()
            
            # 4. 生成 HTML 报告
            html_report = self.generate_html_report(resource_charts, performance_charts)
            
            self.logger.info("报告生成完成!")
            return html_report
            
        except Exception as e:
            self.logger.error(f"报告生成失败: {e}")
            raise

def main():
    parser = argparse.ArgumentParser(description='生成 Trustee Service 性能测试报告')
    parser.add_argument('--test-name', required=True, help='测试名称')
    parser.add_argument('--data-dir', required=True, help='数据目录路径')
    parser.add_argument('--output-dir', required=True, help='输出目录路径')
    parser.add_argument('--log-file', help='日志文件路径')
    
    args = parser.parse_args()
    
    # 配置日志
    if args.log_file:
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(args.log_file),
                logging.StreamHandler()
            ]
        )
    
    try:
        # 创建报告生成器
        generator = TrusteeReportGenerator(
            test_name=args.test_name,
            data_dir=args.data_dir,
            output_dir=args.output_dir
        )
        
        # 生成报告
        report_file = generator.generate_report()
        print(f"报告已生成: {report_file}")
        
    except Exception as e:
        print(f"错误: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()