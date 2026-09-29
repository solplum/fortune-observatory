import { parseObject, jObj, jArr, jObjAt, jStr, jNum, jBool } from '../../common/JsonUtil';

export class QmPair {
  k: string = '';
  v: string = '';
}

export class QmPalace {
  num: number = 0;
  name: string = '';
  dir: string = '';
  sky: string = '';
  earth: string = '';
  star: string = '';
  door: string = '';
  god: string = '';
  center: boolean = false;
}

export class QmPattern {
  name: string = '';
  nature: string = '';
  palace: number = 0;
}

export class QimenParseResult {
  ok: boolean = false;
  caption: string = '';
  pairs: Array<QmPair> = new Array<QmPair>();
  palaces: Array<QmPalace> = new Array<QmPalace>();
  patterns: Array<QmPattern> = new Array<QmPattern>();
}

function pair(k: string, v: string): QmPair {
  const p = new QmPair();
  p.k = k;
  p.v = v;
  return p;
}

/**
 * 解析 POST /v1/qimen/chart 响应（契约 §4.4 qimen/models.py:49-161 字段）。
 * 盘面展示用视图对象在此集中构建，页面只做渲染。
 */
export function parseQimenChart(raw: string): QimenParseResult {
  const result = new QimenParseResult();
  const root = parseObject(raw);
  if (root === null) {
    return result;
  }
  const chart = jObj(root, 'chart');
  const gz = jObj(root, 'ganzhi');
  if (chart === null || gz === null) {
    return result;
  }
  result.caption = `${jStr(root, 'question_type', '')} · ${jStr(root, 'question_goal', '')}`;

  result.pairs.push(pair('公历', jStr(root, 'calendar_solar', '')));
  const cal = jObj(root, 'calendar_lunar');
  if (cal !== null) {
    result.pairs.push(pair('农历', `${jStr(cal, 'month_text', '')}${jStr(cal, 'day_text', '')}`));
  }
  const jq = jObj(root, 'jieqi');
  if (jq !== null) {
    result.pairs.push(pair('节气', `${jStr(jq, 'active_jie', '')} · 下一个 ${jStr(jq, 'next_jie', '')}`));
  }
  result.pairs.push(pair('四柱', `${jStr(gz, 'year', '')} ${jStr(gz, 'month', '')} ${jStr(gz, 'day', '')} ${jStr(gz, 'time', '')}`));
  result.pairs.push(pair('旬首/空亡', `${jStr(gz, 'day_xun_exact', '')} 空 ${jStr(gz, 'day_xunkong_exact', '')}`));
  const zhifu = jObj(chart, 'zhifu');
  if (zhifu !== null) {
    result.pairs.push(pair('值符', `${jStr(zhifu, 'star', '')} 落${jNum(zhifu, 'palace', 0)}宫`));
  }
  const zhishi = jObj(chart, 'zhishi');
  if (zhishi !== null) {
    result.pairs.push(pair('值使', `${jStr(zhishi, 'door', '')} 落${jNum(zhishi, 'palace', 0)}宫`));
  }
  const yima = jObj(chart, 'yima');
  if (yima !== null) {
    result.pairs.push(pair('驿马', `${jStr(yima, 'branch', '')} 落${jNum(yima, 'palace', 0)}宫`));
  }
  result.pairs.push(pair('遁甲', `${jStr(chart, 'dun_type', '')}${jNum(chart, 'ju_number', 0)}局 · 遁${jStr(chart, 'hidden_yi', '')}`));

  const list: Array<Object> = jArr(chart, 'palaces');
  for (let i = 0; i < list.length; i++) {
    const p = jObjAt(list, i);
    if (p === null) {
      continue;
    }
    const cell = new QmPalace();
    cell.num = jNum(p, 'palace', 0);
    cell.name = jStr(p, 'name', '');
    cell.dir = jStr(p, 'direction', '');
    cell.sky = jStr(p, 'sky_stem', '');
    cell.earth = jStr(p, 'earth_stem', '');
    cell.star = jStr(p, 'star', '');
    cell.door = jStr(p, 'door', '');
    cell.god = jStr(p, 'god', '');
    cell.center = jBool(p, 'is_center', false) || jBool(p, 'hosts_center', false);
    result.palaces.push(cell);
  }

  const pats: Array<Object> = jArr(chart, 'detected_patterns');
  for (let i = 0; i < pats.length; i++) {
    const pt = jObjAt(pats, i);
    if (pt === null) {
      continue;
    }
    const item = new QmPattern();
    item.name = jStr(pt, 'name', '');
    item.nature = jStr(pt, 'nature', '');
    item.palace = jNum(pt, 'palace', 0);
    result.patterns.push(item);
  }

  result.ok = result.palaces.length > 0;
  return result;
}
