import { Theme } from '../common/Theme';
import { AppState } from '../common/AppState';
import { apiPost } from '../common/ApiClient';
import { pad2 } from '../common/JsonUtil';
import { resolveShanghaiCivil, CivilCandidate, CIVIL_GAP, CIVIL_OVERLAP } from '../common/ShanghaiTime';
import { BaziBoard } from './boards/BaziBoard';
import { ZiweiBoard } from './boards/ZiweiBoard';
import { QizhengBoard } from './boards/QizhengBoard';

interface ChartReqBody {
  civil_datetime: string;
  timezone_id: string;
  longitude: number;
  latitude: number;
  sex_for_rule: string;
  use_apparent_solar_time: boolean;
}

/**
 * 排盘页：出生资料表单 → POST /v1/charts → 三盘 Tab（八字四柱+五行 / 紫微十二宫 / 七政四余）。
 * civil_datetime 带显式 +08:00 偏移、与 timezone_id=Asia/Shanghai 自洽（契约 §3.1）。
 */
@Component
export struct ChartPage {
  onBack: () => void = () => {
  };
  onCharted: () => void = () => {
  };

  @State date: string = '2000-01-01';
  @State time: string = '08:30';
  @State sex: string = 'male';
  @State lon: string = '104.065';
  @State lat: string = '30.659';
  @State loading: boolean = false;
  @State err: string = '';
  @State hasResult: boolean = false;
  @State chartJson: string = '';

  private sexLabel(): string {
    return this.sex === 'male' ? '男' : '女';
  }

  private validate(): string {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(this.date)) {
      return '出生日期格式应为 YYYY-MM-DD，例如 2000-01-01。';
    }
    if (!/^\d{2}:\d{2}$/.test(this.time)) {
      return '出生时间格式应为 HH:mm，24 小时制。';
    }
    const year: number = parseInt(this.date.substring(0, 4), 10);
    const month: number = parseInt(this.date.substring(5, 7), 10);
    const day: number = parseInt(this.date.substring(8, 10), 10);
    const hour: number = parseInt(this.time.substring(0, 2), 10);
    const minute: number = parseInt(this.time.substring(3, 5), 10);
    if (isNaN(year) || isNaN(month) || isNaN(day) || isNaN(hour) || isNaN(minute)) {
      return '日期或时间无法解析，请检查。';
    }
    if (year < 1849 || year > 2150) {
      return '当前支持 1849-2150 年之间的出生时间。';
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return '月或日超出范围，请检查。';
    }
    if (hour > 23 || minute > 59) {
      return '时间超出范围，请用 24 小时制。';
    }
    const lo: number = parseFloat(this.lon);
    const la: number = parseFloat(this.lat);
    if (isNaN(lo) || lo < -180 || lo > 180) {
      return '经度需在 -180 到 180 之间。';
    }
    if (isNaN(la) || la < -90 || la > 90) {
      return '纬度需在 -90 到 90 之间。';
    }
    return '';
  }

  private async submit(): Promise<void> {
    const bad: string = this.validate();
    if (bad.length > 0) {
      this.err = bad;
      return;
    }
    // 契约 §3.1/§8.12：偏移必须与 timezone_id 在该时刻一致，历史夏令时段先本地判定候选
    const cand = new CivilCandidate();
    const civilKind: number = resolveShanghaiCivil(this.date, this.time, cand);
    if (civilKind === CIVIL_GAP) {
      this.err = '这个当地时间处于历史时制跳变的空缺段（1986-1991 年夏令时开始当日 02:00-02:59 不存在），当前系统不会猜测不存在的时刻。';
      return;
    }
    if (civilKind === CIVIL_OVERLAP) {
      this.err = '这个当地时间处于历史夏令时回拨的重叠段（1986-1991 年，该时刻当天出现两次），当前系统不会替你猜测具体时刻，请把时间前后调整几分钟再试。';
      return;
    }
    this.err = '';
    this.loading = true;
    const body: ChartReqBody = {
      civil_datetime: cand.timestamp,
      timezone_id: 'Asia/Shanghai',
      longitude: parseFloat(this.lon),
      latitude: parseFloat(this.lat),
      sex_for_rule: this.sex,
      use_apparent_solar_time: true
    };
    const resp = await apiPost('/v1/charts', JSON.stringify(body), 20000);
    this.loading = false;
    if (!resp.ok) {
      this.err = resp.error;
      return;
    }
    AppState.shared().setChart(resp.body, JSON.stringify(body),
      `${this.date} ${this.time} ${this.sexLabel()}`);
    this.chartJson = resp.body;
    this.hasResult = true;
    this.onCharted();
  }

  @Builder
  fieldLabel(t: string) {
    Text(t)
      .fontSize(13)
      .fontColor(Theme.MUTED)
      .width('100%')
  }

  @Builder
  sexChip(v: string, label: string) {
    Text(label)
      .fontSize(14)
      .fontColor(this.sex === v ? Theme.INK : Theme.MUTED)
      .textAlign(TextAlign.Center)
      .height(40)
      .layoutWeight(1)
      .borderRadius(10)
      .backgroundColor(this.sex === v ? Theme.WASH : Theme.SURFACE)
      .border({ width: 1, color: this.sex === v ? Theme.LINE : Theme.SOFT_LINE })
      .onClick(() => {
        this.sex = v;
      })
  }

  @Builder
  formView() {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 6 }) {
          Text('出生资料只存在这台设备上')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.INK)
          Text('排盘和运势计算时会发到服务器处理，用完不保存；点「问 AI」类功能才会把盘面事实发给 AI 服务商。')
            .fontSize(12)
            .fontColor(Theme.MUTED)
            .lineHeight(18)
        }
        .padding(12)
        .borderRadius(10)
        .backgroundColor('#FFFDF0')
        .border({ width: 1, color: Theme.SOFT_LINE })
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 6 }) {
          this.fieldLabel('出生日期（公历，YYYY-MM-DD）')
          TextInput({ text: this.date, placeholder: '如 2000-01-01' })
            .height(44)
            .fontSize(15)
            .onChange((v: string) => {
              this.date = v;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 6 }) {
          this.fieldLabel('出生时间（24 小时制，HH:mm）')
          TextInput({ text: this.time, placeholder: '如 08:30' })
            .height(44)
            .fontSize(15)
            .onChange((v: string) => {
              this.time = v;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 6 }) {
          this.fieldLabel('性别')
          Row({ space: 8 }) {
            this.sexChip('male', '男')
            this.sexChip('female', '女')
          }.width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 6 }) {
          this.fieldLabel('出生地经度 / 纬度（用于真太阳时校正）')
          Row({ space: 8 }) {
            TextInput({ text: this.lon, placeholder: '经度 104.065' })
              .height(44)
              .fontSize(15)
              .layoutWeight(1)
              .onChange((v: string) => {
                this.lon = v;
              })
            TextInput({ text: this.lat, placeholder: '纬度 30.659' })
              .height(44)
              .fontSize(15)
              .layoutWeight(1)
              .onChange((v: string) => {
                this.lat = v;
              })
          }.width('100%')
          Text('时区固定 Asia/Shanghai（+08:00），已按真太阳时口径计算。')
            .fontSize(11.5)
            .fontColor(Theme.MUTED)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        if (this.err.length > 0) {
          Text(this.err)
            .fontSize(13.5)
            .fontColor(Theme.ACCENT2)
            .lineHeight(20)
            .width('100%')
        }

        Button(this.loading ? '排盘中…' : '生成命盘')
          .fontSize(16)
          .height(46)
          .width('100%')
          .backgroundColor(Theme.ACCENT)
          .enabled(!this.loading)
          .onClick(() => {
            this.submit();
          })
      }
      .padding(14)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  resultView() {
    Column() {
      Row({ space: 10 }) {
        Text(`档案：${AppState.shared().birthLabel}`)
          .fontSize(12.5)
          .fontColor(Theme.MUTED)
          .layoutWeight(1)
          .maxLines(1)
        Button('重新排盘')
          .fontSize(12.5)
          .height(32)
          .backgroundColor(Theme.SURFACE)
          .fontColor(Theme.INK)
          .border({ width: 1, color: Theme.LINE })
          .onClick(() => {
            this.hasResult = false;
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })

      Tabs({ barPosition: BarPosition.Start }) {
        TabContent() {
          BaziBoard({ chartJson: this.chartJson })
        }.tabBar('八字四柱')

        TabContent() {
          ZiweiBoard({ chartJson: this.chartJson })
        }.tabBar('紫微十二宫')

        TabContent() {
          QizhengBoard({ chartJson: this.chartJson })
        }.tabBar('七政四余')
      }
      .barPosition(BarPosition.Start)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
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
        Text('排盘')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 6 })

      if (this.hasResult) {
        this.resultView()
      } else {
        this.formView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.PAPER)
  }
}
