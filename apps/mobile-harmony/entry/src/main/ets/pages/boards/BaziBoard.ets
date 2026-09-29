import { Theme } from '../../common/Theme';
import { parseObject, jObj, jArr, jObjAt, jStr, jNum } from '../../common/JsonUtil';

const STEM_EL: Record<string, string> = {
  '甲': 'wood', '乙': 'wood',
  '丙': 'fire', '丁': 'fire',
  '戊': 'earth', '己': 'earth',
  '庚': 'metal', '辛': 'metal',
  '壬': 'water', '癸': 'water'
};

const BRANCH_EL: Record<string, string> = {
  '寅': 'wood', '卯': 'wood',
  '巳': 'fire', '午': 'fire',
  '辰': 'earth', '戌': 'earth', '丑': 'earth', '未': 'earth',
  '申': 'metal', '酉': 'metal',
  '亥': 'water', '子': 'water'
};

const EL_NAMES: Record<string, string> = {
  'wood': '木', 'fire': '火', 'earth': '土', 'metal': '金', 'water': '水'
};

function lookupEl(table: Record<string, string>, ch: string): string {
  const v: string | undefined = table[ch];
  return v === undefined ? '' : v;
}

export function elementColor(ch: string): string {
  const el = lookupEl(STEM_EL, ch).length > 0 ? lookupEl(STEM_EL, ch) : lookupEl(BRANCH_EL, ch);
  if (el === 'wood') {
    return Theme.EL_WOOD;
  }
  if (el === 'fire') {
    return Theme.EL_FIRE;
  }
  if (el === 'earth') {
    return Theme.EL_EARTH;
  }
  if (el === 'metal') {
    return Theme.EL_METAL;
  }
  if (el === 'water') {
    return Theme.EL_WATER;
  }
  return Theme.MUTED;
}

class PillarCell {
  label: string = '';
  god: string = '';
  stem: string = '';
  branch: string = '';
  hidden: string = '';
  nayin: string = '';
}

class LuckCell {
  pillar: string = '';
  ages: string = '';
}

class ElCount {
  name: string = '';
  color: string = '';
  count: number = 0;
}

/**
 * 盘一 · 四柱八字（契约 §3.1 bazi 字段）：
 * 四柱（十神/天干/地支/藏干/纳音，干支按五行着色）+ 五行分布 + 起运事实卡 + 大运横条。
 */
@Component
export struct BaziBoard {
  @Prop chartJson: string = '';
  private cells: Array<PillarCell> = new Array<PillarCell>();
  private lucks: Array<LuckCell> = new Array<LuckCell>();
  private elCounts: Array<ElCount> = new Array<ElCount>();
  private lunar: string = '';
  private basis: string = '';
  private qiyunDesc: string = '';

  aboutToAppear(): void {
    const root = parseObject(this.chartJson);
    if (root === null) {
      return;
    }
    const bazi = jObj(root, 'bazi');
    if (bazi === null) {
      return;
    }
    this.lunar = jStr(bazi, 'lunar_date', '');
    const basis = jStr(bazi, 'input_time_basis', '');
    this.basis = basis === 'apparent_solar' ? '真太阳时' : basis;

    const pl = jObj(bazi, 'pillars');
    const labels: Array<string> = ['年柱', '月柱', '日柱', '时柱'];
    const keys: Array<string> = ['year', 'month', 'day', 'hour'];
    const pillars: Array<string> = [];
    for (let i = 0; i < 4; i++) {
      const c = new PillarCell();
      c.label = labels[i];
      if (pl !== null) {
        const p = jStr(pl, keys[i], '');
        pillars.push(p);
        c.stem = p.length > 0 ? p.substring(0, 1) : '';
        c.branch = p.length > 1 ? p.substring(1, 2) : '';
      }
      this.cells.push(c);
    }

    const det: Array<Object> = jArr(bazi, 'pillar_details');
    for (let i = 0; i < det.length && i < 4; i++) {
      const d = jObjAt(det, i);
      if (d === null) {
        continue;
      }
      this.cells[i].god = jStr(d, 'ten_god', '');
      this.cells[i].nayin = jStr(d, 'nayin', '');
      const hidden: Array<Object> = jArr(d, 'hidden_stems');
      const parts: Array<string> = [];
      for (let k = 0; k < hidden.length; k++) {
        const h = jObjAt(hidden, k);
        if (h === null) {
          continue;
        }
        const stem = jStr(h, 'stem', '');
        const god = jStr(h, 'ten_god', '');
        parts.push(stem.length > 0 ? `${stem}·${god}` : god);
      }
      this.cells[i].hidden = parts.join(' ');
    }

    // 五行分布（天干 + 地支逐字计数）
    const tally: Record<string, number> = { 'wood': 0, 'fire': 0, 'earth': 0, 'metal': 0, 'water': 0 };
    for (let i = 0; i < pillars.length; i++) {
      const p = pillars[i];
      for (let k = 0; k < p.length; k++) {
        const ch = p.substring(k, k + 1);
        const el = lookupEl(STEM_EL, ch).length > 0 ? lookupEl(STEM_EL, ch) : lookupEl(BRANCH_EL, ch);
        if (el.length > 0) {
          tally[el] = tally[el] + 1;
        }
      }
    }
    const elKeys: Array<string> = ['wood', 'fire', 'earth', 'metal', 'water'];
    for (let i = 0; i < elKeys.length; i++) {
      const e = new ElCount();
      e.name = EL_NAMES[elKeys[i]];
      e.count = tally[elKeys[i]];
      e.color = elementColor(elKeys[i] === 'wood' ? '甲' : elKeys[i] === 'fire' ? '丙' :
        elKeys[i] === 'earth' ? '戊' : elKeys[i] === 'metal' ? '庚' : '壬');
      this.elCounts.push(e);
    }

    // 起运
    const gs = jObj(bazi, 'great_luck_start');
    if (gs !== null) {
      const dir = jStr(gs, 'direction', '') === 'forward' ? '顺行' : '逆行';
      const first = jStr(gs, 'first_pillar', '');
      const y = jNum(gs, 'years', 0);
      const m = jNum(gs, 'months', 0);
      const dd = jNum(gs, 'days', 0);
      this.qiyunDesc = `${dir}，首运 ${first}，${y}年${m}个月${dd}天后起运`;
    }

    // 大运
    const glp: Array<Object> = jArr(bazi, 'great_luck_periods');
    const maxShow: number = Math.min(glp.length, 8);
    for (let i = 0; i < maxShow; i++) {
      const g = jObjAt(glp, i);
      if (g === null) {
        continue;
      }
      const l = new LuckCell();
      l.pillar = jStr(g, 'pillar', '');
      l.ages = `${jNum(g, 'start_age', 0)}-${jNum(g, 'end_age', 0)}岁`;
      this.lucks.push(l);
    }
  }

  @Builder
  pillarCard(c: PillarCell) {
    Column({ space: 4 }) {
      Text(c.label)
        .fontSize(11)
        .fontColor(Theme.MUTED)
      Text(c.god)
        .fontSize(11)
        .fontColor(Theme.ACCENT)
      Text(c.stem)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(elementColor(c.stem))
      Text(c.branch)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(elementColor(c.branch))
      Text(c.hidden)
        .fontSize(9.5)
        .fontColor(Theme.MUTED)
        .textAlign(TextAlign.Center)
        .maxLines(2)
      Text(c.nayin)
        .fontSize(9.5)
        .fontColor(Theme.MUTED)
        .maxLines(2)
    }
    .layoutWeight(1)
    .padding({ top: 8, bottom: 8, left: 2, right: 2 })
    .borderRadius(10)
    .backgroundColor(Theme.SURFACE)
    .border({ width: 1, color: Theme.SOFT_LINE })
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text(`农历 ${this.lunar} · ${this.basis}口径`)
          .fontSize(12)
          .fontColor(Theme.MUTED)

        Row({ space: 6 }) {
          ForEach(this.cells, (c: PillarCell) => {
            this.pillarCard(c)
          }, (c: PillarCell, idx: number) => `${idx}`)
        }
        .width('100%')

        Column({ space: 6 }) {
          Text('五行分布').fontSize(13).fontColor(Theme.MUTED)
          Row({ space: 12 }) {
            ForEach(this.elCounts, (e: ElCount) => {
              Text(`${e.name} ${e.count}`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(e.color)
            }, (e: ElCount, idx: number) => `${idx}`)
          }
        }
        .padding(12)
        .borderRadius(10)
        .backgroundColor(Theme.SURFACE)
        .border({ width: 1, color: Theme.SOFT_LINE })
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        if (this.qiyunDesc.length > 0) {
          Column({ space: 6 }) {
            Text('起运').fontSize(13).fontColor(Theme.MUTED)
            Text(this.qiyunDesc).fontSize(14).fontColor(Theme.INK)
          }
          .padding(12)
          .borderRadius(10)
          .backgroundColor('#FFFDF0')
          .border({ width: 1, color: Theme.SOFT_LINE })
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        if (this.lucks.length > 0) {
          Column({ space: 6 }) {
            Text('大运').fontSize(13).fontColor(Theme.MUTED)
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.lucks, (l: LuckCell) => {
                  Column({ space: 4 }) {
                    Text(l.pillar)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Theme.INK)
                    Text(l.ages)
                      .fontSize(10.5)
                      .fontColor(Theme.MUTED)
                  }
                  .padding({ top: 8, bottom: 8, left: 12, right: 12 })
                  .borderRadius(10)
                  .backgroundColor(Theme.SURFACE)
                  .border({ width: 1, color: Theme.SOFT_LINE })
                }, (l: LuckCell, idx: number) => `${idx}`)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .padding(14)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}
