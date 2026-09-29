import { Theme } from '../../common/Theme';
import { parseObject, jObj, jArr, jObjAt, jStr, jNum } from '../../common/JsonUtil';

class PalaceCell {
  name: string = '';
  stem: string = '';
  branch: string = '';
  isBody: boolean = false;
  stars: string = '';
  minors: string = '';
  decadal: string = '';
}

const ROW1: Array<string> = ['巳', '午', '未', '申'];
const ROW2: Array<string> = ['辰', '酉'];
const ROW3: Array<string> = ['卯', '戌'];
const ROW4: Array<string> = ['寅', '丑', '子', '亥'];

/**
 * 盘二 · 紫微十二宫（契约 §3.1 ziwei 字段）：
 * 传统 4×4 方阵（十二宫环列 + 中宫信息），主星带亮度与生年四化徽记，身宫角标。
 */
@Component
export struct ZiweiBoard {
  @Prop chartJson: string = '';
  private byBranch: Record<string, PalaceCell> = {};
  private lifeBranch: string = '';
  private bodyBranch: string = '';
  private bureau: number = 0;
  private yearStem: string = '';
  private mutagenSummary: string = '';
  private lunarMonth: number = 0;
  private hourBranch: string = '';

  aboutToAppear(): void {
    const root = parseObject(this.chartJson);
    if (root === null) {
      return;
    }
    const zw = jObj(root, 'ziwei');
    if (zw === null) {
      return;
    }
    this.lifeBranch = jStr(zw, 'life_branch', '');
    this.bodyBranch = jStr(zw, 'body_branch', '');
    this.bureau = jNum(zw, 'five_elements_bureau', 0);
    this.yearStem = jStr(zw, 'year_stem', '');
    this.lunarMonth = jNum(zw, 'lunar_month', 0);
    this.hourBranch = jStr(zw, 'hour_branch', '');

    // 生年四化：星 → 禄/权/科/忌
    const mutagenMap: Record<string, string> = {};
    const bm: Array<Object> = jArr(zw, 'birth_mutagens');
    const mutParts: Array<string> = [];
    for (let i = 0; i < bm.length; i++) {
      const m = jObjAt(bm, i);
      if (m === null) {
        continue;
      }
      const star = jStr(m, 'star', '');
      const mu = jStr(m, 'mutagen', '');
      if (star.length > 0) {
        mutagenMap[star] = mu;
        mutParts.push(`${star}${mu}`);
      }
    }
    this.mutagenSummary = mutParts.join(' · ');

    // 主星亮度
    const palaces: Array<Object> = jArr(zw, 'palaces');
    for (let i = 0; i < palaces.length; i++) {
      const p = jObjAt(palaces, i);
      if (p === null) {
        continue;
      }
      const cell = new PalaceCell();
      cell.name = jStr(p, 'name', '');
      cell.stem = jStr(p, 'stem', '');
      cell.branch = jStr(p, 'branch', '');
      cell.isBody = cell.branch === this.bodyBranch && this.bodyBranch.length > 0;

      const brightMap: Record<string, string> = {};
      const brights: Array<Object> = jArr(p, 'major_star_brightness');
      for (let k = 0; k < brights.length; k++) {
        if (Array.isArray(brights[k])) {
          const arr = brights[k] as Array<Object>;
          if (arr.length >= 2) {
            brightMap[jStr2(arr[0])] = jStr2(arr[1]);
          }
        }
      }

      const majors: Array<Object> = jArr(p, 'major_stars');
      const starParts: Array<string> = [];
      for (let k = 0; k < majors.length; k++) {
        const star = jStr2(majors[k]);
        let label = star;
        const br = brightMap[star];
        if (br !== undefined && br.length > 0) {
          label += `(${br})`;
        }
        const mu = mutagenMap[star];
        if (mu !== undefined && mu.length > 0) {
          label += mu;
        }
        starParts.push(label);
      }
      cell.stars = starParts.join(' ');

      const minors: Array<Object> = jArr(p, 'minor_stars');
      const minorParts: Array<string> = [];
      for (let k = 0; k < minors.length; k++) {
        minorParts.push(jStr2(minors[k]));
      }
      cell.minors = minorParts.join(' ');

      const drRaw: Array<Object> = jArr(p, 'decadal_range');
      if (drRaw.length >= 2) {
        cell.decadal = `${jNum2(drRaw[0])}-${jNum2(drRaw[1])}岁`;
      }
      this.byBranch[cell.branch] = cell;
    }
  }

  private cellAt(branch: string): PalaceCell | null {
    const v: PalaceCell | undefined = this.byBranch[branch];
    return v === undefined ? null : v;
  }

  @Builder
  palaceCell(branch: string) {
    Column({ space: 2 }) {
      if (this.cellAt(branch) === null) {
        Text(branch).fontSize(11).fontColor(Theme.MUTED)
      } else {
        Text(`${(this.cellAt(branch) as PalaceCell).name}${(this.cellAt(branch) as PalaceCell).isBody ? '·身' : ''}`)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.ACCENT)
          .maxLines(1)
        Text(`${(this.cellAt(branch) as PalaceCell).stem}${branch}`)
          .fontSize(9)
          .fontColor(Theme.MUTED)
        if ((this.cellAt(branch) as PalaceCell).stars.length > 0) {
          Text((this.cellAt(branch) as PalaceCell).stars)
            .fontSize(9.5)
            .fontColor(Theme.INK)
            .maxLines(2)
        }
        if ((this.cellAt(branch) as PalaceCell).minors.length > 0) {
          Text((this.cellAt(branch) as PalaceCell).minors)
            .fontSize(8.5)
            .fontColor(Theme.MUTED)
            .maxLines(1)
        }
        Text((this.cellAt(branch) as PalaceCell).decadal)
          .fontSize(8.5)
          .fontColor(Theme.MUTED)
      }
    }
    .layoutWeight(1)
    .height(84)
    .justifyContent(FlexAlign.Center)
    .padding(3)
    .borderRadius(8)
    .backgroundColor(Theme.SURFACE)
    .border({ width: 1, color: branch === this.lifeBranch ? Theme.ACCENT : Theme.SOFT_LINE })
  }

  @Builder
  centerCell(title: string, lines: string) {
    Column({ space: 3 }) {
      Text(title)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.ACCENT)
      Text(lines)
        .fontSize(9.5)
        .fontColor(Theme.INK)
        .lineHeight(14)
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(2)
    .height(84)
    .justifyContent(FlexAlign.Center)
    .padding(4)
    .borderRadius(8)
    .backgroundColor('#FFFDF0')
    .border({ width: 1, color: Theme.SOFT_LINE })
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Text(`命宫在${this.lifeBranch} · 身宫在${this.bodyBranch} · ${this.bureau}局 · ${this.lunarMonth}月生 · ${this.hourBranch}时`)
          .fontSize(12)
          .fontColor(Theme.MUTED)

        Row({ space: 4 }) {
          this.palaceCell(ROW1[0])
          this.palaceCell(ROW1[1])
          this.palaceCell(ROW1[2])
          this.palaceCell(ROW1[3])
        }.width('100%')

        Row({ space: 4 }) {
          this.palaceCell(ROW2[0])
          this.centerCell('命宫 · 五行局', `命宫${this.lifeBranch} · ${this.bureau}局\n年干${this.yearStem}`)
          this.palaceCell(ROW2[1])
        }.width('100%')

        Row({ space: 4 }) {
          this.palaceCell(ROW3[0])
          this.centerCell('生年四化', this.mutagenSummary.length > 0 ? this.mutagenSummary : '—')
          this.palaceCell(ROW3[1])
        }.width('100%')

        Row({ space: 4 }) {
          this.palaceCell(ROW4[0])
          this.palaceCell(ROW4[1])
          this.palaceCell(ROW4[2])
          this.palaceCell(ROW4[3])
        }.width('100%')

        Text('主星括号内为亮度，星名后缀禄/权/科/忌为生年四化；蓝框为命宫。')
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

// 数组元素取值的局部辅助（Array<Object> 里的原始值）
function jStr2(v: Object | undefined): string {
  if (typeof v === 'string') {
    return v as string;
  }
  return '';
}

function jNum2(v: Object | undefined): number {
  if (typeof v === 'number') {
    return v as number;
  }
  return 0;
}
