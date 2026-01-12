/**
 * 「狙い台抽出」(A1から表) → 「狙い台一覧」へ集計出力
 *
 * ============================================================================
 * 【評価方法の詳細説明】
 * ============================================================================
 * 
 * 複数の戦略で推奨されている台を、より信頼性の高い順に並べるために、
 * 以下の4つの指標を組み合わせて総合スコアを算出します。
 * 
 * ----------------------------------------------------------------------------
 * 1. 重み付け平均機械割・勝率（参照台数で重み付け）
 * ----------------------------------------------------------------------------
 * 【目的】
 *   サンプルサイズが大きい戦略の結果をより重視する
 * 
 * 【計算方法】
 *   例: 台番1227が以下の3つの戦略で推奨されている場合
 *   - 戦略A: 機械割122.71%, 勝率63.6%, 参照台数10台
 *   - 戦略B: 機械割115.50%, 勝率50.0%, 参照台数50台
 *   - 戦略C: 機械割110.00%, 勝率40.0%, 参照台数5台
 * 
 *   重み付け平均機械割 = (122.71×10 + 115.50×50 + 110.00×5) / (10+50+5)
 *                      = (1227.1 + 5775 + 550) / 65
 *                      = 7552.1 / 65
 *                      = 116.19% → 1.1619（0-1の範囲に変換）
 * 
 *   重み付け平均勝率 = (63.6×10 + 50.0×50 + 40.0×5) / (10+50+5)
 *                    = (636 + 2500 + 200) / 65
 *                    = 3336 / 65
 *                    = 51.32% → 0.5132（0-1の範囲に変換）
 * 
 * 【意味】
 *   参照台数が多い戦略（サンプルサイズが大きい）の結果をより重視することで、
 *   より信頼性の高い評価が可能になります。
 * 
 * ----------------------------------------------------------------------------
 * 2. RMS（Root Mean Square: 二乗平均平方根）
 * ----------------------------------------------------------------------------
 * 【目的】
 *   機械割と勝率のバランスを評価する
 * 
 * 【計算方法】
 *   RMS = sqrt((重み付け平均機械割^2 + 重み付け平均勝率^2) / 2)
 * 
 *   例: 重み付け平均機械割=1.1619, 重み付け平均勝率=0.5132 の場合
 *   RMS = sqrt((1.1619^2 + 0.5132^2) / 2)
 *       = sqrt((1.3500 + 0.2634) / 2)
 *       = sqrt(0.8067)
 *       = 0.8982
 * 
 * 【意味】
 *   機械割と勝率の両方が高い場合に高くなる指標です。
 *   どちらか一方だけが高くても、RMSはそれほど高くなりません。
 *   バランスの良い台を評価できます。
 * 
 * ----------------------------------------------------------------------------
 * 3. 信頼性スコア（サンプルサイズを考慮）
 * ----------------------------------------------------------------------------
 * 【目的】
 *   実施日数と参照台数の合計が多いほど、その戦略の結果は信頼性が高い
 * 
 * 【計算方法】
 *   1. 各戦略の「実施日数 + 参照台数」を合計
 *   2. 全台番の中で最大値を求める
 *   3. 各台番の合計値を最大値で割る（正規化、0-1の範囲）
 * 
 *   例: 台番1227の合計が100、最大値が500の場合
 *   信頼性スコア = 100 / 500 = 0.20
 * 
 *   例: 台番1228の合計が450、最大値が500の場合
 *   信頼性スコア = 450 / 500 = 0.90
 * 
 * 【意味】
 *   サンプルサイズが大きい戦略の結果ほど信頼性が高いため、
 *   その戦略で推奨されている台の信頼性も高くなります。
 * 
 * ----------------------------------------------------------------------------
 * 4. 出現頻度ボーナス
 * ----------------------------------------------------------------------------
 * 【目的】
 *   複数の戦略で推奨されている台は、より信頼性が高い
 * 
 * 【計算方法】
 *   1. 各台番の「該当数」（出現回数）を求める
 *   2. 全台番の中で最大値を求める
 *   3. 各台番の該当数の平方根を最大値の平方根で割る（正規化、0-1の範囲）
 * 
 *   例: 台番1227の該当数が4回、最大値が16回の場合
 *   出現頻度ボーナス = sqrt(4) / sqrt(16) = 2 / 4 = 0.50
 * 
 *   例: 台番1228の該当数が9回、最大値が16回の場合
 *   出現頻度ボーナス = sqrt(9) / sqrt(16) = 3 / 4 = 0.75
 * 
 * 【意味】
 *   平方根を使うことで、出現数が多いほどボーナスが増えますが、
 *   増加率は減ります（例: 1回→4回は2倍、4回→9回は1.5倍）。
 *   これにより、複数の戦略で推奨されている台を優先しつつ、
 *   極端に多い出現数による過大評価を防ぎます。
 * 
 * ----------------------------------------------------------------------------
 * 5. 総合スコア
 * ----------------------------------------------------------------------------
 * 【目的】
 *   上記の3つの指標を組み合わせて、より信頼性が高く、
 *   複数の戦略で推奨されている台を優先する
 * 
 * 【計算方法】
 *   総合スコア = RMS × 信頼性スコア × 出現頻度ボーナス
 * 
 *   例: RMS=0.8982, 信頼性スコア=0.90, 出現頻度ボーナス=0.75 の場合
 *   総合スコア = 0.8982 × 0.90 × 0.75
 *              = 0.6063
 * 
 * 【意味】
 *   - RMSが高い: 機械割と勝率のバランスが良い
 *   - 信頼性スコアが高い: サンプルサイズが大きく、信頼性が高い
 *   - 出現頻度ボーナスが高い: 複数の戦略で推奨されている
 * 
 *   これらを掛け合わせることで、より信頼性が高く、
 *   複数の戦略で推奨されている台を優先できます。
 * 
 * ============================================================================
 * 【出力カラム】
 * ============================================================================
 * - 日付: 次の日
 * - 台番: 該当台番
 * - 総合スコア: RMS × 信頼性スコア × 出現頻度ボーナス（降順ソート）
 * - 該当数: 出現回数
 * - 重み付け平均機械割: 参照台数で重み付けした機械割の平均（0-1の範囲、例: 1.1619）
 * - 重み付け平均勝率: 参照台数で重み付けした勝率の平均（0-1の範囲、例: 0.5132）
 * - 信頼性スコア: 実施日数と参照台数の合計を正規化（0-1の範囲）
 * - 出現頻度ボーナス: 該当数の平方根を正規化（0-1の範囲）
 *
 * ============================================================================
 * 【注意事項】
 * ============================================================================
 * - 「勝率」「機械割」は「%表記の数値(文字列に%なし)」前提。
 *   すでに 0.636 みたいな小数で入ってるなら /100 を外してね。
 * - 「該当台番」は "1227, 1268" のようにカンマ区切り + 空白ありを想定。全角「、」も許容。
 * - 「参照台数」「実施日数」が存在しない場合は、重み=1、日数=0として扱います。
 */
function buildNeraiDaiIchiran() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const srcName = '狙い台抽出';
  const dstName = '狙い台一覧';

  const src = ss.getSheetByName(srcName);
  if (!src) throw new Error(`シートが見つからない: ${srcName}`);

  const lastRow = src.getLastRow();
  const lastCol = src.getLastColumn();

  // 出力先だけ用意して終わり
  if (lastRow < 2) {
    const dst = prepareDstSheet_(ss, dstName);
    dst.clear({ contentsOnly: true });
    dst.getRange(1, 1, 1, 8).setValues([[
      '日付', '台番', '総合スコア', '該当数', '重み付け平均機械割', '重み付け平均勝率', 
      '信頼性スコア', '出現頻度ボーナス'
    ]]);
    dst.setFrozenRows(1);
    autosizeWithHeaderMin_(dst, 8, 1, 90, 420);
    return;
  }

  const values = src.getRange(1, 1, lastRow, lastCol).getValues();
  const headers = values[0].map(h => String(h).trim());

  const idxNextDay = findCol_(headers, ['次の日', '次の日付', '次回', '翌日']);
  const idxTargets = findCol_(headers, ['該当台番', '対象台番', '台番']);
  const idxWinRate = findCol_(headers, ['勝率']);
  const idxMachine = findCol_(headers, ['機械割']);
  const idxRefCount = findCol_(headers, ['参照台数', '対象台数']);
  const idxDays = findCol_(headers, ['実施日数', '日数']);

  if (idxNextDay === -1) throw new Error('ヘッダ「次の日」が見つからない');
  if (idxTargets === -1) throw new Error('ヘッダ「該当台番」が見つからない');
  if (idxWinRate === -1) throw new Error('ヘッダ「勝率」が見つからない');
  if (idxMachine === -1) throw new Error('ヘッダ「機械割」が見つからない');

  const tz = Session.getScriptTimeZone();

  // key: `${dateKey}|${dai}`
  /** @type {Map<string, {
   *   date: Date, 
   *   dai: string, 
   *   count: number, 
   *   totalWeight: number,
   *   weightedMachine: number, 
   *   weightedWinRate: number,
   *   totalDays: number,
   *   totalRefCount: number
   * }>} */
  const map = new Map();

  for (let r = 1; r < values.length; r++) {
    const row = values[r];
    if (row.every(v => v === '' || v === null)) continue;

    const dateObj = toDate_(row[idxNextDay]);
    if (!dateObj) continue;

    // 時刻を切り落として日付だけにする
    const dateOnly = new Date(dateObj.getFullYear(), dateObj.getMonth(), dateObj.getDate());
    const dateKey = Utilities.formatDate(dateOnly, tz, 'yyyy-MM-dd');

    const dais = splitTargets_(row[idxTargets]);
    if (dais.length === 0) continue;

    const wr = toNumber_(row[idxWinRate]) / 100;   // %表記の数値 -> 0-1へ
    const mw = toNumber_(row[idxMachine]) / 100;   // %表記の数値 -> 0-1へ
    
    // 重み（参照台数、なければ1）
    const weight = Math.max(toNumber_(row[idxRefCount] || 0), 1);
    const days = toNumber_(row[idxDays] || 0);
    const refCount = toNumber_(row[idxRefCount] || 0);

    for (const dai of dais) {
      const key = `${dateKey}|${dai}`;
      if (!map.has(key)) {
        map.set(key, { 
          date: dateOnly, 
          dai, 
          count: 0, 
          totalWeight: 0,
          weightedMachine: 0, 
          weightedWinRate: 0,
          totalDays: 0,
          totalRefCount: 0
        });
      }
      const obj = map.get(key);
      obj.count += 1;
      obj.totalWeight += weight;
      obj.weightedMachine += (isFinite(mw) ? mw * weight : 0);
      obj.weightedWinRate += (isFinite(wr) ? wr * weight : 0);
      obj.totalDays += days;
      obj.totalRefCount += refCount;
    }
  }

  // 最大値を計算（正規化用）
  let maxDays = 0;
  let maxRefCount = 0;
  let maxCount = 0;
  for (const obj of map.values()) {
    if (obj.totalDays > maxDays) maxDays = obj.totalDays;
    if (obj.totalRefCount > maxRefCount) maxRefCount = obj.totalRefCount;
    if (obj.count > maxCount) maxCount = obj.count;
  }

  // 出力配列作成
  const out = [];
  out.push([
    '日付', '台番', '総合スコア', '該当数', '重み付け平均機械割', '重み付け平均勝率', 
    '信頼性スコア', '出現頻度ボーナス'
  ]);

  const rows = Array.from(map.values()).map(o => {
    // 重み付け平均
    const avgMachine = o.totalWeight > 0 ? o.weightedMachine / o.totalWeight : 0;
    const avgWinRate = o.totalWeight > 0 ? o.weightedWinRate / o.totalWeight : 0;
    
    // RMS（機械割と勝率のバランス）
    const rms = Math.sqrt((avgMachine * avgMachine + avgWinRate * avgWinRate) / 2);
    
    // 信頼性スコア（実施日数と参照台数の合計を正規化）
    // 最大値で正規化、ただし最大値が0の場合は1とする
    const reliabilityScore = (maxDays + maxRefCount) > 0 
      ? Math.min((o.totalDays + o.totalRefCount) / (maxDays + maxRefCount), 1.0)
      : 1.0;
    
    // 出現頻度ボーナス（該当数の平方根を正規化）
    // 平方根を使うことで、出現数が多いほどボーナスが増えるが、増加率は減る
    const frequencyBonus = maxCount > 0 
      ? Math.min(Math.sqrt(o.count) / Math.sqrt(maxCount), 1.0)
      : 1.0;
    
    // 総合スコア: RMS × 信頼性スコア × 出現頻度ボーナス
    const totalScore = rms * reliabilityScore * frequencyBonus;
    
    return [
      o.date, 
      o.dai, 
      totalScore,  // 総合スコアを3列目に
      o.count, 
      avgMachine, 
      avgWinRate, 
      reliabilityScore, 
      frequencyBonus
    ];
  });

  // ソート: 日付昇順 → 総合スコア降順 → 台番昇順
  rows.sort((a, b) => {
    const d = a[0].getTime() - b[0].getTime();
    if (d !== 0) return d;
    const s = b[2] - a[2];  // 総合スコア降順（3列目=インデックス2）
    if (s !== 0) return s;

    const an = Number(a[1]), bn = Number(b[1]);
    if (Number.isFinite(an) && Number.isFinite(bn)) return an - bn;
    return String(a[1]).localeCompare(String(b[1]));
  });

  out.push(...rows);

  // 書き込み
  const dst = prepareDstSheet_(ss, dstName);
  dst.clear({ contentsOnly: true });
  dst.getRange(1, 1, out.length, out[0].length).setValues(out);

  // 見た目
  dst.setFrozenRows(1);

  // 見出し幅を考慮してから autosize
  autosizeWithHeaderMin_(dst, out[0].length, 1, 90, 420);

  // フォーマット
  const dataRows = Math.max(out.length - 1, 1);

  // A: 日付
  dst.getRange(2, 1, dataRows, 1).setNumberFormat('yyyy-mm-dd');
  // C: 総合スコア（小数3桁）
  dst.getRange(2, 3, dataRows, 1).setNumberFormat('0.000');
  // D: 該当数
  dst.getRange(2, 4, dataRows, 1).setNumberFormat('0');
  // E/F/G/H: 加重・スコア（小数3桁）
  dst.getRange(2, 5, dataRows, 4).setNumberFormat('0.000');

  // フィルタ
  if (out.length >= 2) {
    const range = dst.getRange(1, 1, out.length, out[0].length);
    if (dst.getFilter()) dst.getFilter().remove();
    range.createFilter();
  }
}

/** スプレッドシートを開いた時にメニュー追加 */
function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('狙い台')
    .addItem('狙い台一覧を更新', 'buildNeraiDaiIchiran')
    .addToUi();
}

/** ヘッダから列インデックスを探す（見つからなければ -1） */
function findCol_(headers, candidates) {
  for (const name of candidates) {
    const idx = headers.indexOf(String(name).trim());
    if (idx !== -1) return idx;
  }
  return -1;
}

/** 該当台番セルを分割して台番配列にする */
function splitTargets_(v) {
  if (v === null || v === '') return [];
  const s = String(v);

  // カンマ , または 全角 、 で分割。前後の空白はトリム。
  return s
    .split(/[,\u3001]/g)
    .map(x => String(x).trim())
    .filter(x => x.length > 0);
}

/** Date っぽい値を Date に */
function toDate_(v) {
  if (!v) return null;
  if (v instanceof Date && !isNaN(v.getTime())) return v;

  const s = String(v).trim();
  if (!s) return null;

  // "2026/01/11" や "2026-01-11" を想定
  const d = new Date(s);
  if (!isNaN(d.getTime())) return d;

  const s2 = s.replace(/\//g, '-');
  const d2 = new Date(s2);
  if (!isNaN(d2.getTime())) return d2;

  return null;
}

/** 数値変換（NaNなら 0） */
function toNumber_(v) {
  if (typeof v === 'number') return v;
  if (v === null || v === '') return 0;
  const n = parseFloat(String(v).replace(/,/g, '').trim());
  return Number.isFinite(n) ? n : 0;
}

/** 出力先シートを用意して返す */
function prepareDstSheet_(ss, name) {
  let sh = ss.getSheetByName(name);
  if (!sh) sh = ss.insertSheet(name);
  return sh;
}

/**
 * ヘッダ文字数を元に「最低幅」を設定してから autoResize する
 * minPx: 最低幅の下限
 * maxPx: 広がりすぎ防止（0やnullなら無制限）
 */
function autosizeWithHeaderMin_(sheet, numCols, headerRow, minPx, maxPx) {
  const headers = sheet.getRange(headerRow, 1, 1, numCols).getDisplayValues()[0];

  // まずヘッダ基準で最低幅を確保
  for (let c = 1; c <= numCols; c++) {
    const text = String(headers[c - 1] ?? '');
    const units = estimateTextUnits_(text);
    let px = Math.ceil(units * 9 + 24); // 余白込み

    if (minPx && px < minPx) px = minPx;
    if (maxPx && maxPx > 0 && px > maxPx) px = maxPx;

    sheet.setColumnWidth(c, px);
  }

  // 次にデータに合わせて自動調整
  sheet.autoResizeColumns(1, numCols);

  // autoResize の結果がヘッダ最低幅より小さかったら戻す
  for (let c = 1; c <= numCols; c++) {
    const text = String(headers[c - 1] ?? '');
    const units = estimateTextUnits_(text);
    let px = Math.ceil(units * 9 + 24);

    if (minPx && px < minPx) px = minPx;
    if (maxPx && maxPx > 0 && px > maxPx) px = maxPx;

    const current = sheet.getColumnWidth(c);
    if (current < px) sheet.setColumnWidth(c, px);
  }
}

function estimateTextUnits_(s) {
  let units = 0;
  for (const ch of s) {
    // ASCII は半角、それ以外は全角扱いでざっくり
    units += ch.charCodeAt(0) <= 0x7f ? 1 : 2;
  }
  return units;
}

