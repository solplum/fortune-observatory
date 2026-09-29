import { Theme } from '../../common/Theme';
import { parseObject, jObj, jArr, jObjAt, jStr, jNum } from '../../common/JsonUtil';

class QzBody {
  name: string = '';
  mansion: string = '';
  dignity: string = '';
  relation: string = '';
  longitude: string = '';
  motion: string = '';
}

class LimitRow {
  palace: string = '';
  branch: string = '';
  years: string = '';
  segment: string = '';
}

const BODY_NAMES: Record<string, string> = {
  'sun': '太阳', 'moon': '太阴', 'mercury': '水星', 'venus': '金星',
  'mars': '火星', 'jupiter': '木星', 'saturn': '土星',
  'rx': '罗睺', 'ketu': '计都', 'csouth': '计都', 'cnorth': '紫气', 'cseal': '月孛'
};

const LORD_NAMES: Record<string, string> = {
  'sun': '太阳', 'moon': '太阴', 'mercury': '水星', 'venus': '金星',
  'mars': '火星', 'jupiter': '木星', 'saturn': '土星'
};

function bodyName(code: string): string {
  const v: string | undefined = BODY_NAMES[code];
  return v === undefined ? code : v;
}

function lordName(code: string): string {
  const v: string | undefined = LORD_NAMES[code];
  return v === undefined ? code : v;
}

/**
 * 盘三 · 七政四余（契约 §3.1 qizheng.traditional 字段）：
 * 星曜入宿行度明细（宿/庙旺徽/恩难仇用/逆行标）+ 命主身主 + 童限 + 洞微大限行限表。
 */
@Component
export struct QizhengBoard {
  @Prop chartJson: string = '';
  private bodies: Array<QzBody> = new Array<QzBody>();
  private limits: Array<LimitRow> = new Array<LimitRow>();
  private lifeLord: string = '';
  private bodyLord: string = '';
  private exitAge: string = '';
  private dayChart: string = '';
  private lifeBranch: string = '';
  private bodyBranch: string = '';
  private anchored: string = '';

  aboutToAppear(): void {
    const root = parseObject(this.chartJson);
    if (root === null) {
      return;
    }
    const qz = jObj(root, 'qizheng');
    if (qz === null) {
      return;
    }
    const tr = jObj(qz, 'traditional');
    if (tr === null) {
      return;
    }
    this.lifeLord = lordName(jStr(tr, 'life_lord', ''));
    this.bodyLord = lordName(jStr(tr, 'body_lord', ''));
    this.dayChart = jBoolStr(tr, 'is_day_chart');
    this.exitAge = `${jNum(tr, 'childhood_exit_age', 0)}`;
    this.lifeBranch = jStr(tr, 'life_branch', '');
    this.bodyBranch = jStr(tr, 'body_branch', '');
    this.anchored = jStr(tr, 'anchor', '');

    const list: Array<Object> = jArr(tr, 'bodies');
    for (let i = 0; i < list.length; i++) {
      const b = jObjAt(list, i);
      if (b === null) {
        continue;
      }
      const row = new QzBody();
      row.name = bodyName(jStr(b, 'body', ''));
      row.mansion = jStr(b, 'mansion', '');
      row.dignity = jStr(b, 'dignity', '');
      row.relation = jStr(b, 'relation', '');
      const deg = jNum(b, 'longitude_deg', 0);
      row.longitude = `${deg.toFixed(1)}°`;
      row.motion = jStr(b, 'motion', '') === 'retrograde' ? '逆' : '';
      this.bodies.push(row);
    }

    const rows: Array<Object> = jArr(tr, 'limit_rows');
    for (let i = 0; i < rows.length; i++) {
      const r = jObjAt(rows, i);
      if (r === null) {
        continue;
      }
      const lr = new LimitRow();
      lr.palace = jStr(r, 'palace', '');
      lr.branch = jStr(r, 'branch', '');
      const start = jNum(r, 'start_age', 0);
      const end = jNum(r, 'end_age', 0);
      lr.years = `${jNum(r, 'years', 0)}岁限 ${start.toFixed(1)}-${end.toFixed(1)}`;
      lr.segment = jStr(r, 'segment', '');
      this.limits.push(lr);
    }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text(`命主 ${this.lifeLord} · 身主 ${this.bodyLord} · ${this.dayChart} · 约${this.exitAge}岁出童限 · 命宫在${this.lifeBranch} 身宫在${this.bodyBranch}`)
          .fontSize(12)
          .fontColor(Theme.MUTED)
          .lineHeight(18)

        Column({ space: 8 }) {
          Text('星曜入宿行度').fontSize(13).fontColor(Theme.MUTED)
          Row({ space: 8 }) {
            Text('星曜').fontSize(11).fontColor(Theme.MUTED).width(52)
            Text('入宿').fontSize(11).fontColor(Theme.MUTED).width(40)
            Text('庙旺').fontSize(11).fontColor(Theme.MUTED).width(44)
            Text('恩难').fontSize(11).fontColor(Theme.MUTED).width(40)
            Text('行度').fontSize(11).fontColor(Theme.MUTED).layoutWeight(1)
          }.width('100%')
          ForEach(this.bodies, (b: QzBody) => {
            Row({ space: 8 }) {
              Text(b.motion.length > 0 ? `${b.name}逆` : b.name)
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(b.motion.length > 0 ? Theme.ACCENT2 : Theme.INK)
                .width(52)
              Text(b.mansion).fontSize(12.5).fontColor(Theme.INK).width(40)
              Text(b.dignity).fontSize(12.5).fontColor(Theme.ACCENT).width(44)
              Text(b.relation).fontSize(12.5).fontColor(Theme.MUTED).width(40)
              Text(b.longitude).fontSize(12.5).fontColor(Theme.MUTED).layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
            .border({ width: { bottom: 1 }, color: Theme.SOFT_LINE })
          }, (b: QzBody, idx: number) => `${idx}`)
        }
        .padding(12)
        .borderRadius(10)
        .backgroundColor(Theme.SURFACE)
        .border({ width: 1, color: Theme.SOFT_LINE })
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        if (this.limits.length > 0) {
          Column({ space: 8 }) {
            Text('洞微大限 · 行限表').fontSize(13).fontColor(Theme.MUTED)
            ForEach(this.limits, (l: LimitRow) => {
              Row({ space: 8 }) {
                Text(`${l.palace}·${l.branch}`)
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.INK)
                  .width(84)
                Text(l.years).fontSize(12.5).fontColor(Theme.MUTED).layoutWeight(1)
                Text(l.segment).fontSize(12.5).fontColor(Theme.ACCENT).width(28)
              }
              .width('100%')
              .padding({ top: 5, bottom: 5 })
              .border({ width: { bottom: 1 }, color: Theme.SOFT_LINE })
            }, (l: LimitRow, idx: number) => `${idx}`)
          }
          .padding(12)
          .borderRadius(10)
          .backgroundColor(Theme.SURFACE)
          .border({ width: 1, color: Theme.SOFT_LINE })
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        Text(`锚定口径：${this.anchored === 'j2000_mean_ecliptic' ? 'J2000 平黄道' : this.anchored}；传统层为规则化整理结果，仅供参考。`)
          .fontSize(11)
          .fontColor(Theme.MUTED)
          .lineHeight(17)
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

function jBoolStr(o: Record<string, Object>, key: string): string {
  const v: Object | undefined = o[key];
  if (typeof v === 'boolean') {
    return (v as boolean) ? '昼盘' : '夜盘';
  }
  return '';
}
