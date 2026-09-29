/**
 * 上海历史时制解析（对齐 Web 端 App.tsx:51-67 的 shanghaiCivilCandidates 双偏移候选法）。
 *
 * tzdata Rule PRC：1986 年夏令时自 5 月 4 日 02:00 起；1987-1991 年为首个周日≥4/10 的 02:00 起
 * （拨快 1 小时，02:00-02:59 墙钟不存在 = 空缺段）；1986-1991 年均为首个周日≥9/11 的 02:00 拨回
 * （01:00-01:59 墙钟出现两次 = 重叠段）。契约 §3.1 要求 civil_datetime 偏移与 timezone_id 在该
 * 时刻一致，否则 422，故提交前在本地完成候选判定。
 */

export const CIVIL_GAP: number = 0;      // 空缺段：该墙钟时刻不存在
export const CIVIL_UNIQUE: number = 1;   // 唯一候选
export const CIVIL_OVERLAP: number = 2;  // 重叠段：该墙钟时刻出现两次（Web 端拒绝猜测）

export class CivilCandidate {
  timestamp: string = '';
}

function isSunday(y: number, m: number, d: number): boolean {
  return new Date(y, m - 1, d).getDay() === 0;
}

function firstSundayOnOrAfter(y: number, m: number, d: number): number {
  let day: number = d;
  for (let i = 0; i < 8; i++) {
    if (isSunday(y, m, day)) {
      return day;
    }
    day += 1;
  }
  return day;
}

function dstStartMonth(y: number): number {
  return y === 1986 ? 5 : 4;
}

function dstStartDay(y: number): number {
  return y === 1986 ? 4 : firstSundayOnOrAfter(y, 4, 10);
}

function dstEndDay(y: number): number {
  return firstSundayOnOrAfter(y, 9, 11);
}

/**
 * 判定给定上海墙钟时刻的 civil_datetime 候选。
 * 返回 CIVIL_GAP / CIVIL_OVERLAP / CIVIL_UNIQUE；
 * 仅 CIVIL_UNIQUE 时 out.timestamp 才被写入（形如 `1988-08-01T10:30:00+09:00`）。
 */
export function resolveShanghaiCivil(date: string, time: string, out: CivilCandidate): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !/^\d{2}:\d{2}$/.test(time)) {
    return CIVIL_GAP; // 格式不合法（调用方已先行校验格式，此处兜底）
  }
  const y: number = parseInt(date.substring(0, 4), 10);
  const mo: number = parseInt(date.substring(5, 7), 10);
  const d: number = parseInt(date.substring(8, 10), 10);
  const hh: number = parseInt(time.substring(0, 2), 10);
  const mm: number = parseInt(time.substring(3, 5), 10);
  if (isNaN(y) || isNaN(mo) || isNaN(d) || isNaN(hh) || isNaN(mm)) {
    return CIVIL_GAP;
  }

  let inDst: boolean = false;
  let gap: boolean = false;
  let overlap: boolean = false;
  if (y >= 1986 && y <= 1991) {
    const sm: number = dstStartMonth(y);
    const sd: number = dstStartDay(y);
    const ed: number = dstEndDay(y);
    const dayNum: number = y * 10000 + mo * 100 + d;
    const startDayNum: number = y * 10000 + sm * 100 + sd;
    const endDayNum: number = y * 10000 + 9 * 100 + ed;
    const mod: number = hh * 60 + mm;

    if (dayNum < startDayNum) {
      inDst = false;
    } else if (dayNum === startDayNum) {
      if (mod <= 120) {
        inDst = false;            // 02:00 整为跳变瞬间，标准时 02:00 存在
      } else if (mod < 180) {
        gap = true;               // 02:00-02:59 被拨快跳过，不存在
      } else {
        inDst = true;
      }
    } else if (dayNum < endDayNum) {
      inDst = true;
    } else if (dayNum === endDayNum) {
      if (mod < 60) {
        inDst = true;             // 00:00-00:59 仍为夏令时
      } else if (mod < 120) {
        overlap = true;           // 01:00-01:59 出现两次
      } else {
        inDst = false;            // 02:00 起恢复标准时
      }
    } else {
      inDst = false;
    }
  }

  if (gap) {
    return CIVIL_GAP;
  }
  if (overlap) {
    return CIVIL_OVERLAP;
  }
  out.timestamp = `${date}T${time}:00${inDst ? '+09:00' : '+08:00'}`;
  return CIVIL_UNIQUE;
}
