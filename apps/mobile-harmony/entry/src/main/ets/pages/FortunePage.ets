import { Theme } from '../common/Theme';
import { AppState } from '../common/AppState';
import { apiPost } from '../common/ApiClient';
import { parseObject, jObj, jArr, jObjAt, jStr, jNum, pad2 } from '../common/JsonUtil';
import { GateCard } from '../components/GateCard';

class FactLine {
  text: string = '';
}

class DayCell {
  date: string = '';
  pillar: string = '';
  tag: string = '';
  facts: string = '';
}

const REL_LABELS: Record<string, string> = {
  'branch_clash': '冲',
  'branch_combination': '合',
  'branch_same': '同'
};

function relLabel(rel: string): string {
  const v: string | undefined = REL_LABELS[rel];
  return v === undefined ? rel : v;
}

/** 北京时间（UTC+8 无夏令时）日历日——产品「今天」全按北京口径（契约 §5.3） */
function beijingNow(): Date {
  const now = new Date();
  return new Date(now.getTime() + (now.getTimezoneOffset() + 480) * 60000);
}

function fmtDate(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

function addDays(d: Date, n: number): Date {
  return new Date(d.getTime() + n * 86400000);
}

/**
 * 运势页：今日/明日 → POST /v1/transits/daily；本周/本月 → POST /v1/transits/window。
 * 周期口径与 Web 对齐：本周=周一至周日、本月=自然月（契约 §3.3）。
 */
@Component
export struct FortunePage {
  onBack: () => void = () => {
  };
  onGoChart: () => void = () => {
  };

  @State scope: string = 'today';
  @State loading: boolean = false;
  @State err: string = '';
  @State rangeLabel: string = '';
  @State dayPillar: string = '';
  @State tags: Array<string> = new Array<string>();
  @State factLines: Array<FactLine> = new Array<FactLine>();
  @State ziweiLines: Array<string> = new Array<string>();
  @State days: Array<DayCell> = new Array<DayCell>();

  aboutToAppear(): void {
    this.load();
  }

  private hasChart(): boolean {
    return AppState.shared().hasChart();
  }

  private windowRange(scope: string): [string, string] {
    const b = beijingNow();
    if (scope === 'week') {
      const monday: Date = addDays(b, -((b.getDay() + 6) % 7));
      const sunday: Date = addDays(monday, 6);
      return [fmtDate(monday), fmtDate(sunday)];
    }
    const monthStart: Date = new Date(b.getFullYear(), b.getMonth(), 1);
    const monthEnd: Date = new Date(b.getFullYear(), b.getMonth() + 1, 0);
    return [fmtDate(monthStart), fmtDate(monthEnd)];
  }

  private deriveTag(hasClash: boolean, hasComb: boolean, factCount: number): string {
    if (hasClash) {
      return '变动日';
    }
    if (hasComb) {
      return '顺合日';
    }
    if (factCount > 0) {
      return '平稳日';
    }
    return '平常日';
  }

  private async load(): Promise<void> {
    if (!this.hasChart()) {
      return;
    }
    this.loading = true;
    this.err = '';
    this.dayPillar = '';
    this.tags = [];
    this.factLines = [];
    this.ziweiLines = [];
    this.days = [];
    this.rangeLabel = '';

    const app = AppState.shared();
    const scope = this.scope;
    if (scope === 'today' || scope === 'tomorrow') {
      const offset: number = scope === 'today' ? 0 : 1;
      const d: string = fmtDate(addDays(beijingNow(), offset));
      this.rangeLabel = scope === 'today' ? `今日 · ${d}` : `明日 · ${d}`;
      const body: string = `{"birth":${app.birthJson},"transit_date":"${d}"}`;
      const resp = await apiPost('/v1/transits/daily', body, 20000);
      this.loading = false;
      if (!resp.ok) {
        this.err = resp.error;
        return;
      }
      this.parseDaily(resp.body);
    } else {
      const range: [string, string] = this.windowRange(scope);
      this.rangeLabel = scope === 'week'
        ? `本周 · ${range[0]} 至 ${range[1]}` : `本月 · ${range[0]} 至 ${range[1]}`;
      const body: string = `{"birth":${app.birthJson},"start_date":"${range[0]}","end_date":"${range[1]}"}`;
      const resp = await apiPost('/v1/transits/window', body, 20000);
      this.loading = false;
      if (!resp.ok) {
        this.err = resp.error;
        return;
      }
      this.parseWindow(resp.body);
    }
  }

  private parseDaily(raw: string): void {
    const root = parseObject(raw);
    if (root === null) {
      this.err = '响应解析失败。';
      return;
    }
    const transit = jObj(root, 'transit');
    if (transit === null) {
      this.err = '响应缺少 transit 字段。';
      return;
    }
    this.dayPillar = jStr(transit, 'day_pillar', '');
    let hasClash = false;
    let hasComb = false;
    const facts: Array<Object> = jArr(transit, 'facts');
    for (let i = 0; i < facts.length; i++) {
      const f = jObjAt(facts, i);
      if (f === null) {
        continue;
      }
      const rel = jStr(f, 'relation', '');
      if (rel === 'branch_clash') {
        hasClash = true;
      }
      if (rel === 'branch_combination') {
        hasComb = true;
      }
      const line = new FactLine();
      line.text = `${jStr(f, 'natal_pillar', '')} 与流日 ${jStr(f, 'transit_pillar', '')} 相${relLabel(rel)}`;
      this.factLines.push(line);
    }
    this.tags.push(this.deriveTag(hasClash, hasComb, facts.length));

    const zy = jObj(root, 'ziwei_yearly');
    if (zy !== null) {
      this.ziweiLines.push(`流年 ${jStr(zy, 'year_pillar', '')}（虚岁 ${jNum(zy, 'nominal_age', 0)}）`);
      const ym: Array<Object> = jArr(zy, 'yearly_mutagens');
      for (let i = 0; i < ym.length; i++) {
        const m = jObjAt(ym, i);
        if (m === null) {
          continue;
        }
        this.ziweiLines.push(`${jStr(m, 'star', '')}化${jStr(m, 'mutagen', '')}入${jStr(m, 'palace_name', '')}（${jStr(m, 'palace_branch', '')}）`);
      }
      const dec = jObj(zy, 'decadal');
      if (dec !== null) {
        this.ziweiLines.push(`大限 ${jNum(dec, 'start_age', 0)}-${jNum(dec, 'end_age', 0)} 岁（${jStr(dec, 'branch', '')}宫）`);
      }
      const fs: Array<Object> = jArr(zy, 'flowing_stars');
      const parts: Array<string> = [];
      for (let i = 0; i < fs.length; i++) {
        const s = jObjAt(fs, i);
        if (s === null) {
          continue;
        }
        parts.push(`${jStr(s, 'star', '')}在${jStr(s, 'branch', '')}`);
      }
      if (parts.length > 0) {
        this.ziweiLines.push(`流曜：${parts.join('、')}`);
      }
    }
  }

  private parseWindow(raw: string): void {
    const root = parseObject(raw);
    if (root === null) {
      this.err = '响应解析失败。';
      return;
    }
    const transit = jObj(root, 'transit');
    if (transit === null) {
      this.err = '响应缺少 transit 字段。';
      return;
    }
    const daily: Array<Object> = jArr(transit, 'daily');
    for (let i = 0; i < daily.length; i++) {
      const d = jObjAt(daily, i);
      if (d === null) {
        continue;
      }
      const cell = new DayCell();
      cell.date = jStr(d, 'transit_date', '');
      cell.pillar = jStr(d, 'day_pillar', '');
      let hasClash = false;
      let hasComb = false;
      const facts: Array<Object> = jArr(d, 'facts');
      const parts: Array<string> = [];
      for (let k = 0; k < facts.length; k++) {
        const f = jObjAt(facts, k);
        if (f === null) {
          continue;
        }
        const rel = jStr(f, 'relation', '');
        if (rel === 'branch_clash') {
          hasClash = true;
        }
        if (rel === 'branch_combination') {
          hasComb = true;
        }
        parts.push(`${jStr(f, 'natal_pillar', '')}${relLabel(rel)}${jStr(f, 'transit_pillar', '')}`);
      }
      cell.tag = this.deriveTag(hasClash, hasComb, facts.length);
      cell.facts = parts.join('　');
      this.days.push(cell);
    }
  }

  @Builder
  scopeChip(v: string, label: string) {
    Text(label)
      .fontSize(13.5)
      .fontColor(this.scope === v ? Theme.INK : Theme.MUTED)
      .textAlign(TextAlign.Center)
      .height(36)
      .layoutWeight(1)
      .borderRadius(9)
      .backgroundColor(this.scope === v ? Theme.WASH : Theme.SURFACE)
      .border({ width: 1, color: this.scope === v ? Theme.LINE : Theme.SOFT_LINE })
      .onClick(() => {
        if (this.scope !== v && !this.loading) {
          this.scope = v;
          this.load();
        }
      })
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('←')
          .fontSize(22)
          .fontColor(Theme.INK)
          .onClick(() => {
            this.onBack();
          })
          .padding({ right: 4 })
        Text('运势')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 6 })

      if (!this.hasChart()) {
        Column() {
          GateCard({
            message: '运势按你的出生时间计算。先完成一次排盘，再看今日、明日、本周与本月。',
            actionText: '去排盘',
            onAction: (): void => {
              this.onGoChart();
            }
          })
        }
        .width('100%')
        .padding(14)
      } else {
        Scroll() {
          Column({ space: 12 }) {
            Row({ space: 6 }) {
              this.scopeChip('today', '今日')
              this.scopeChip('tomorrow', '明日')
              this.scopeChip('week', '本周')
              this.scopeChip('month', '本月')
            }.width('100%')

            if (this.loading) {
              Row({ space: 8 }) {
                LoadingProgress().width(18).height(18).color(Theme.ACCENT)
                Text('计算中…').fontSize(13.5).fontColor(Theme.MUTED)
              }.width('100%')
            }

            if (this.err.length > 0) {
              Text(this.err)
                .fontSize(13.5)
                .fontColor(Theme.ACCENT2)
                .lineHeight(20)
                .width('100%')
            }

            if (this.dayPillar.length > 0) {
              Column({ space: 10 }) {
                Row({ space: 8 }) {
                  Text(this.dayPillar)
                    .fontSize(26)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.INK)
                  ForEach(this.tags, (t: string) => {
                    Text(t)
                      .fontSize(12)
                      .fontColor(Theme.INK)
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .borderRadius(8)
                      .backgroundColor(Theme.WASH)
                  }, (t: string, idx: number) => `${idx}`)
                }
                if (this.factLines.length > 0) {
                  ForEach(this.factLines, (f: FactLine) => {
                    Text(f.text).fontSize(14).fontColor(Theme.INK).lineHeight(21)
                  }, (f: FactLine, idx: number) => `${idx}`)
                } else {
                  Text('今日与命局四柱无冲合关系。').fontSize(14).fontColor(Theme.MUTED)
                }
              }
              .padding(14)
              .borderRadius(Theme.RADIUS)
              .backgroundColor(Theme.SURFACE)
              .border({ width: 1, color: Theme.SOFT_LINE })
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            if (this.ziweiLines.length > 0) {
              Column({ space: 6 }) {
                Text('紫微流年').fontSize(13).fontColor(Theme.MUTED)
                ForEach(this.ziweiLines, (l: string) => {
                  Text(l).fontSize(13.5).fontColor(Theme.INK).lineHeight(20)
                }, (l: string, idx: number) => `${idx}`)
              }
              .padding(12)
              .borderRadius(10)
              .backgroundColor(Theme.SURFACE)
              .border({ width: 1, color: Theme.SOFT_LINE })
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            if (this.days.length > 0) {
              Column({ space: 8 }) {
                Text(this.rangeLabel).fontSize(13).fontColor(Theme.MUTED)
                ForEach(this.days, (d: DayCell) => {
                  Column({ space: 4 }) {
                    Row({ space: 8 }) {
                      Text(d.date).fontSize(13).fontColor(Theme.MUTED).layoutWeight(1)
                      Text(d.tag)
                        .fontSize(11)
                        .fontColor(d.tag === '变动日' ? Theme.ACCENT2 : Theme.INK)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .borderRadius(6)
                        .backgroundColor(d.tag === '变动日' ? '#FFE4E6' : Theme.WASH)
                    }
                    .width('100%')
                    Text(`${d.pillar}日`).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Theme.INK)
                    if (d.facts.length > 0) {
                      Text(d.facts).fontSize(12).fontColor(Theme.MUTED).lineHeight(18)
                    }
                  }
                  .padding(10)
                  .borderRadius(10)
                  .backgroundColor(Theme.SURFACE)
                  .border({ width: 1, color: Theme.SOFT_LINE })
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                }, (d: DayCell, idx: number) => `${idx}`)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }
          .padding(14)
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.PAPER)
  }
}
