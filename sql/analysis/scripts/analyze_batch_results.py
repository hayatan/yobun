#!/usr/bin/env python3
"""
バッチ評価結果の分析スクリプト
BigQueryの実行結果CSVを解析し、60日と120日の比較、各メソッドの比較を行います。
THRESHOLD_98/99%を重視し、人間が判断できる余地を残したレポートを生成します。
"""

import pandas as pd
from collections import defaultdict
import sys

def load_data(csv_file):
    """CSVファイルを読み込む"""
    df = pd.read_csv(csv_file)
    print(f"読み込み行数: {len(df)}", file=sys.stderr)
    
    # データ型変換
    for col in ['win_rate', 'payout_rate', 'avg_diff', 'avg_machines_per_day']:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')
    
    return df

def analyze_combination(df, hole, machine, days, special_day_type):
    """特定の組み合わせを分析"""
    subset = df[
        (df['target_hole'] == hole) &
        (df['target_machine'] == machine) &
        (df['evaluation_days'] == days) &
        (df['special_day_type'] == special_day_type)
    ]
    
    if len(subset) == 0:
        return None
    
    results = {
        'evaluation_days_count': subset['evaluation_days_count'].iloc[0],
        'methods': {}
    }
    
    for method in subset['score_method'].unique():
        method_data = subset[subset['score_method'] == method]
        
        # TOP1
        top1 = method_data[method_data['result_key'] == 'TOP1']
        if len(top1) == 0:
            continue
            
        top1_row = top1.iloc[0]
        
        method_results = {
            'TOP1': {
                'win_rate': top1_row['win_rate'],
                'payout_rate': top1_row['payout_rate'],
                'avg_diff': top1_row['avg_diff'],
                'avg_machines': 1.0
            }
        }
        
        # THRESHOLD結果
        for threshold in ['THRESHOLD_95PCT', 'THRESHOLD_96PCT', 'THRESHOLD_97PCT', 
                         'THRESHOLD_98PCT', 'THRESHOLD_99PCT']:
            th_data = method_data[method_data['result_key'] == threshold]
            if len(th_data) > 0:
                th_row = th_data.iloc[0]
                method_results[threshold] = {
                    'win_rate': th_row['win_rate'],
                    'payout_rate': th_row['payout_rate'],
                    'avg_diff': th_row['avg_diff'],
                    'avg_machines': th_row['avg_machines_per_day']
                }
        
        results['methods'][method] = method_results
    
    return results

def generate_method_comparison_table(results, focus_thresholds=['TOP1', 'THRESHOLD_98PCT', 'THRESHOLD_99PCT']):
    """メソッド比較テーブルを生成"""
    rows = []
    for method, data in sorted(results['methods'].items()):
        row = {'method': method}
        for th in focus_thresholds:
            if th in data:
                row[f'{th}_win_rate'] = data[th]['win_rate']
                row[f'{th}_payout_rate'] = data[th]['payout_rate']
                row[f'{th}_avg_diff'] = data[th]['avg_diff']
                row[f'{th}_avg_machines'] = data[th]['avg_machines']
            else:
                row[f'{th}_win_rate'] = None
                row[f'{th}_payout_rate'] = None
                row[f'{th}_avg_diff'] = None
                row[f'{th}_avg_machines'] = None
        rows.append(row)
    return rows

def print_markdown_report(df):
    """マークダウン形式のレポートを出力"""
    
    # 全組み合わせを取得
    combinations = df[['target_hole', 'target_machine', 'evaluation_days', 'special_day_type']].drop_duplicates()
    
    # 店舗ごとにグループ化
    by_store = defaultdict(list)
    for _, row in combinations.iterrows():
        by_store[row['target_hole']].append((row['target_machine'], row['evaluation_days'], row['special_day_type']))
    
    print("# 評価結果詳細分析レポート")
    print()
    print("## 📋 概要")
    print()
    print("このレポートは、各店舗・機種・評価期間について、全8種類のスコアメソッドを評価した結果です。")
    print("**TOP1だけでなく、THRESHOLD_98%/99%（2〜3台に絞れる閾値）も重視**して分析しています。")
    print()
    print("### 評価対象")
    print()
    for store, machines in sorted(by_store.items()):
        print(f"- **{store}**")
        unique_machines = sorted(set(m[0] for m in machines))
        for m in unique_machines:
            print(f"  - {m}")
    print()
    print("### 評価期間")
    print("- 60日間")
    print("- 120日間")
    print()
    print("---")
    print()
    
    # 各店舗・機種ごとに分析
    for store in sorted(by_store.keys()):
        print(f"## 📍 {store}")
        print()
        
        # 機種ごとにグループ化
        machines_data = defaultdict(list)
        for machine, days, special_day_type in by_store[store]:
            machines_data[machine].append((days, special_day_type))
        
        for machine in sorted(machines_data.keys()):
            print(f"### 🎰 {machine}")
            print()
            
            # 60日と120日のデータを取得
            for days, special_day_type in sorted(machines_data[machine]):
                results = analyze_combination(df, store, machine, days, special_day_type)
                if results is None:
                    continue
                
                print(f"#### {days}日評価（評価日数: {results['evaluation_days_count']}日）")
                print()
                
                # メソッド比較テーブル（TOP1, THRESHOLD_98%, THRESHOLD_99%）
                print("##### メソッド比較（TOP1 / THRESHOLD_98% / THRESHOLD_99%）")
                print()
                print("| メソッド | TOP1勝率 | TOP1機械割 | 98%勝率 | 98%機械割 | 98%台数 | 99%勝率 | 99%機械割 | 99%台数 |")
                print("|----------|----------|------------|---------|-----------|---------|---------|-----------|---------|")
                
                comparison = generate_method_comparison_table(results)
                for row in comparison:
                    top1_wr = f"{row['TOP1_win_rate']:.1f}%" if row['TOP1_win_rate'] is not None else "-"
                    top1_pr = f"{row['TOP1_payout_rate']:.2f}%" if row['TOP1_payout_rate'] is not None else "-"
                    
                    th98_wr = f"{row['THRESHOLD_98PCT_win_rate']:.1f}%" if row.get('THRESHOLD_98PCT_win_rate') is not None else "-"
                    th98_pr = f"{row['THRESHOLD_98PCT_payout_rate']:.2f}%" if row.get('THRESHOLD_98PCT_payout_rate') is not None else "-"
                    th98_m = f"{row['THRESHOLD_98PCT_avg_machines']:.2f}" if row.get('THRESHOLD_98PCT_avg_machines') is not None else "-"
                    
                    th99_wr = f"{row['THRESHOLD_99PCT_win_rate']:.1f}%" if row.get('THRESHOLD_99PCT_win_rate') is not None else "-"
                    th99_pr = f"{row['THRESHOLD_99PCT_payout_rate']:.2f}%" if row.get('THRESHOLD_99PCT_payout_rate') is not None else "-"
                    th99_m = f"{row['THRESHOLD_99PCT_avg_machines']:.2f}" if row.get('THRESHOLD_99PCT_avg_machines') is not None else "-"
                    
                    print(f"| `{row['method']}` | {top1_wr} | {top1_pr} | {th98_wr} | {th98_pr} | {th98_m} | {th99_wr} | {th99_pr} | {th99_m} |")
                
                print()
                
                # 推奨の判断材料を提示
                print("##### 📊 判断材料")
                print()
                
                # TOP1で最高成績のメソッド
                best_top1_method = None
                best_top1_payout = -1
                for method, data in results['methods'].items():
                    if 'TOP1' in data and data['TOP1']['payout_rate'] > best_top1_payout:
                        best_top1_payout = data['TOP1']['payout_rate']
                        best_top1_method = method
                
                # THRESHOLD_98%で最高成績のメソッド（台数1.0-2.0）
                best_th98_method = None
                best_th98_payout = -1
                best_th98_machines = None
                for method, data in results['methods'].items():
                    if 'THRESHOLD_98PCT' in data:
                        th_data = data['THRESHOLD_98PCT']
                        if 1.0 <= th_data['avg_machines'] <= 2.0 and th_data['payout_rate'] > best_th98_payout:
                            best_th98_payout = th_data['payout_rate']
                            best_th98_method = method
                            best_th98_machines = th_data['avg_machines']
                
                # THRESHOLD_99%で最高成績のメソッド（台数1.0-1.5）
                best_th99_method = None
                best_th99_payout = -1
                best_th99_machines = None
                for method, data in results['methods'].items():
                    if 'THRESHOLD_99PCT' in data:
                        th_data = data['THRESHOLD_99PCT']
                        if 1.0 <= th_data['avg_machines'] <= 1.5 and th_data['payout_rate'] > best_th99_payout:
                            best_th99_payout = th_data['payout_rate']
                            best_th99_method = method
                            best_th99_machines = th_data['avg_machines']
                
                if best_top1_method:
                    print(f"- **TOP1最高機械割**: `{best_top1_method}` ({best_top1_payout:.2f}%)")
                
                if best_th98_method:
                    print(f"- **THRESHOLD_98%最高機械割**: `{best_th98_method}` ({best_th98_payout:.2f}%, 平均{best_th98_machines:.2f}台)")
                
                if best_th99_method:
                    print(f"- **THRESHOLD_99%最高機械割**: `{best_th99_method}` ({best_th99_payout:.2f}%, 平均{best_th99_machines:.2f}台)")
                
                # TOP1とTHRESHOLD_98/99%の機械割差を計算
                if best_top1_method and best_th98_method:
                    top1_data = results['methods'][best_top1_method]['TOP1']
                    th98_data = results['methods'][best_th98_method].get('THRESHOLD_98PCT')
                    if th98_data:
                        diff = top1_data['payout_rate'] - th98_data['payout_rate']
                        if abs(diff) < 1.0:
                            print(f"- ⭐ TOP1とTHRESHOLD_98%の機械割差は{diff:.2f}%（1%未満）")
                
                print()
            
            # 60日 vs 120日の比較
            print("#### 📈 60日 vs 120日 比較")
            print()
            
            results_60 = analyze_combination(df, store, machine, 60, 'island' if 'アイランド' in store else 'espas')
            results_120 = analyze_combination(df, store, machine, 120, 'island' if 'アイランド' in store else 'espas')
            
            if results_60 and results_120:
                print("| メソッド | 60日TOP1機械割 | 120日TOP1機械割 | 差 | 60日99%機械割 | 120日99%機械割 | 差 |")
                print("|----------|----------------|-----------------|-----|---------------|-----------------|-----|")
                
                methods = set(results_60['methods'].keys()) | set(results_120['methods'].keys())
                for method in sorted(methods):
                    d60_top1 = results_60['methods'].get(method, {}).get('TOP1', {}).get('payout_rate')
                    d120_top1 = results_120['methods'].get(method, {}).get('TOP1', {}).get('payout_rate')
                    top1_diff = d120_top1 - d60_top1 if d60_top1 and d120_top1 else None
                    
                    d60_th99 = results_60['methods'].get(method, {}).get('THRESHOLD_99PCT', {}).get('payout_rate')
                    d120_th99 = results_120['methods'].get(method, {}).get('THRESHOLD_99PCT', {}).get('payout_rate')
                    th99_diff = d120_th99 - d60_th99 if d60_th99 and d120_th99 else None
                    
                    d60_top1_str = f"{d60_top1:.2f}%" if d60_top1 else "-"
                    d120_top1_str = f"{d120_top1:.2f}%" if d120_top1 else "-"
                    top1_diff_str = f"{top1_diff:+.2f}%" if top1_diff is not None else "-"
                    
                    d60_th99_str = f"{d60_th99:.2f}%" if d60_th99 else "-"
                    d120_th99_str = f"{d120_th99:.2f}%" if d120_th99 else "-"
                    th99_diff_str = f"{th99_diff:+.2f}%" if th99_diff is not None else "-"
                    
                    print(f"| `{method}` | {d60_top1_str} | {d120_top1_str} | {top1_diff_str} | {d60_th99_str} | {d120_th99_str} | {th99_diff_str} |")
                
                print()
            
            print("---")
            print()
    
    # 全体サマリー
    print("## 📝 全体サマリー")
    print()
    print("### 判断ガイドライン")
    print()
    print("1. **1台狙いなら**: TOP1の機械割が最も高いメソッドを選択")
    print("2. **2〜3台狙いなら**: THRESHOLD_98%またはTHRESHOLD_99%の成績を重視")
    print("3. **TOP1とTHRESHOLD_98/99%の機械割差が1%未満なら**: THRESHOLD_98/99%を選んだ方が動きやすい")
    print("4. **60日と120日で傾向が異なる場合**: より新しい60日のデータを参考にしつつ、120日で安定しているメソッドも検討")
    print()
    print("### クエリ実行時のパラメータ選択")
    print()
    print("狙い台抽出クエリ `tolove_recommendation_output.sql` を実行する際は:")
    print()
    print("1. このレポートを参考に、対象店舗・機種に最適なメソッドを選択")
    print("2. `score_method` パラメータを設定")
    print("3. 閾値は `THRESHOLD_98PCT` または `THRESHOLD_99PCT` を推奨")
    print()

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_batch_results.py <csv_file>", file=sys.stderr)
        sys.exit(1)
    
    csv_file = sys.argv[1]
    df = load_data(csv_file)
    print_markdown_report(df)
