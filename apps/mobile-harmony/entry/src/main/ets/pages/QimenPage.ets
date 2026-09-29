import { Theme } from '../common/Theme';
import { AppState } from '../common/AppState';
import { apiPost } from '../common/ApiClient';
import { Pacer } from '../common/Pacer';
import { SseEvent, SseSession, startStream, stopActiveStream } from '../common/SseClient';
import { StreamResult } from '../components/StreamResult';
import { QimenParseResult, QmPair, QmPalace, QmPattern, parseQimenChart } from './qimen/QimenParse';

interface QimenReqBody {
  question_type: string;
  question_goal: string;
  time_mode: string;
  time_input: string | null;
  city: string;
  detail_level: string;
}

// 洛书九宫排布：上排 4 9 2，中排 3 5 7，下排 8 1 6
const GRID: Array<Array<number>> = [[4, 9, 2], [3, 5, 7], [8, 1, 6]];
const JI_COLOR: string = '#2F9E44';

/**
 * 奇门遁甲页：起局表单 → POST /v1/qimen/chart（确定性计算）
 * → 九宫盘面 + 摘要 → POST /v1/qimen/interpret/stream（SSE，整盘原样回传）。
 */
@Component
export struct QimenPage {
  onBack: () => void = () => {
  };

  @State qType: string = '事业';
  @State goal: string = '';
  @State timeMode: string = 'now';
  @State customTime: string = '';
  @State city: string = '';
  @State level: string = 'brief';
  @State loading: boolean = false;
  @State err: string = '';
  @State hasChart: boolean = false;

  @State pairs: Array<QmPair> = new Array<QmPair>();
  @State palaces: Array<QmPalace> = new Array<QmPalace>();
  @State patterns: Array<QmPattern> = new Array<QmPattern>();
  @State chartCaption: string = '';

  @State phase: string = 'idle';
  @State think: string = '';
  @State shown: string = '';
  @State streamErr: string = '';
  private pacer: Pacer = new Pacer();
  private session: SseSession | null = null;

  private types: Array<string> = ['事业', '求财', '感情', '学业', '健康', '出行', '诉讼', '寻人寻物', '其他'];

  aboutToAppear(): void {
    this.pacer.onTick = (text: string, tk: string, drained: boolean) => {
      this.shown = text;
      this.think = tk;
      if (drained) {
        this.pacer.stop();
      }
    };
  }

  aboutToDisappear(): void {
    this.pacer.stop();
    stopActiveStream();
  }

  private palaceAt(num: number): QmPalace | null {
    for (let i = 0; i < this.palaces.length; i++) {
      if (this.palaces[i].num === num) {
        return this.palaces[i];
      }
    }
    return null;
  }

  private async submit(): Promise<void> {
    const goal: string = this.goal.trim();
    if (goal.length < 2 || goal.length > 120) {
      this.err = '所问之事请写 2-120 字。';
      return;
    }
    if (this.timeMode === 'custom') {
      const t: string = this.customTime.trim();
      if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(t)) {
        this.err = '指定时间格式应为 YYYY-MM-DD HH:mm，例如 2026-10-01 10:00。';
        return;
      }
    }
    this.err = '';
    this.loading = true;
    const body: QimenReqBody = {
      question_type: this.qType,
      question_goal: goal,
      time_mode: this.timeMode,
      time_input: this.timeMode === 'custom' ? this.customTime.trim() : null,
      city: this.city.trim(),
      detail_level: this.level
    };
    const resp = await apiPost('/v1/qimen/chart', JSON.stringify(body), 20000);
    this.loading = false;
    if (!resp.ok) {
      this.err = resp.error;
      return;
    }
    const parsed: QimenParseResult = parseQimenChart(resp.body);
    if (!parsed.ok) {
      this.err = '盘面解析失败。';
      return;
    }
    AppState.shared().setQimen(resp.body);
    this.pairs = parsed.pairs;
    this.palaces = parsed.palaces;
    this.patterns = parsed.patterns;
    this.chartCaption = parsed.caption;
    this.hasChart = true;
    this.phase = 'idle';
    this.shown = '';
    this.think = '';
    this.streamErr = '';
  }

  private handleEvent(evt: SseEvent): void {
    if (evt.type === 'think') {
      this.pacer.appendFullThink(evt.text);
      if (this.phase !== 'streaming') {
        this.phase = 'thinking';
      }
      this.pacer.start();
    } else if (evt.type === 'delta') {
      this.pacer.appendFullText(evt.text);
      this.phase = 'streaming';
      this.pacer.start();
    } else if (evt.type === 'done') {
      this.pacer.markInputDone();
      this.phase = 'done';
    } else if (evt.type === 'error') {
      this.pacer.markInputDone();
      if (evt.code === 'safety') {
        this.pacer.reset();
        this.shown = '';
        this.think = '';
      }
      this.streamErr = evt.detail.length > 0 ? evt.detail : '读盘失败，请稍后重试。';
      this.phase = 'error';
    }
  }

  private startInterpret(): void {
    const raw: string = AppState.shared().qimenJson;
    if (raw.length === 0) {
      this.streamErr = '尚未起局，请先起局再读盘。';
      return;
    }
    this.streamErr = '';
    this.pacer.reset();
    this.shown = '';
    this.think = '';
    this.phase = 'connecting';
    // 契约 §4.5：解读只消费回传盘面，整响应原样回传（extra=forbid，不得增删字段）
    const body: string = `{"chart":${raw}}`;
    const self = this;
    this.session = startStream('/v1/qimen/interpret/stream', body, {
      onEvent: (evt: SseEvent): void => {
        self.handleEvent(evt);
      },
      onReset: (): void => {
        self.pacer.reset();
        self.shown = '';
        self.think = '';
        self.phase = 'connecting';
      },
      onFatal: (): void => {
      }
    });
  }

  private stopStream(): void {
    stopActiveStream();
    this.pacer.markInputDone();
    this.phase = 'done';
  }

  @Builder
  modeChip(current: string, v: string, label: string, onPick: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(current === v ? Theme.INK : Theme.MUTED)
      .textAlign(TextAlign.Center)
      .height(34)
      .layoutWeight(1)
      .borderRadius(8)
      .backgroundColor(current === v ? Theme.WASH : Theme.SURFACE)
      .border({ width: 1, color: current === v ? Theme.LINE : Theme.SOFT_LINE })
      .onClick(() => {
        onPick();
      })
  }

  @Builder
  palaceCell(num: number) {
    Column({ space: 2 }) {
      if (this.palaceAt(num) === null) {
        Text(`${num}`).fontSize(10).fontColor(Theme.MUTED)
      } else {
        Text(`${(this.palaceAt(num) as QmPalace).sky} / ${(this.palaceAt(num) as QmPalace).earth}`)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.ACCENT)
        Text(`${(this.palaceAt(num) as QmPalace).star} · ${(this.palaceAt(num) as QmPalace).door}`)
          .fontSize(9.5)
          .fontColor(Theme.INK)
          .maxLines(1)
        Text(`${(this.palaceAt(num) as QmPalace).god} · ${(this.palaceAt(num) as QmPalace).name}(${(this.palaceAt(num) as QmPalace).dir})`)
          .fontSize(8.5)
          .fontColor(Theme.MUTED)
          .maxLines(1)
      }
    }
    .layoutWeight(1)
    .height(72)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor(num === 5 ? '#FFFDF0' : Theme.SURFACE)
    .border({ width: 1, color: Theme.SOFT_LINE })
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
        Text('奇门遁甲')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 6 })

      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 6 }) {
            Text('所问事项类别')
              .fontSize(13)
              .fontColor(Theme.MUTED)
            Select(this.typeOptions())
              .selected(0)
              .value(this.qType)
              .font({ size: 14 })
              .height(40)
              .width('100%')
              .onSelect((index: number) => {
                if (index >= 0 && index < this.types.length) {
                  this.qType = this.types[index];
                }
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 6 }) {
            Text('所问之事（2-120 字，感情类可写明男问女/女问男）')
              .fontSize(13)
              .fontColor(Theme.MUTED)
            TextArea({ text: this.goal, placeholder: '例如：下个月跳槽顺不顺' })
              .height(72)
              .fontSize(14.5)
              .maxLength(120)
              .onChange((v: string) => {
                this.goal = v;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 6 }) {
            Text('起局时间')
              .fontSize(13)
              .fontColor(Theme.MUTED)
            Row({ space: 8 }) {
              this.modeChip(this.timeMode, 'now', '就现在', (): void => {
                this.timeMode = 'now';
              })
              this.modeChip(this.timeMode, 'custom', '指定时间', (): void => {
                this.timeMode = 'custom';
              })
            }.width('100%')
            if (this.timeMode === 'custom') {
              TextInput({ text: this.customTime, placeholder: 'YYYY-MM-DD HH:mm，如 2026-10-01 10:00' })
                .height(44)
                .fontSize(14)
                .onChange((v: string) => {
                  this.customTime = v;
                })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 6 }) {
            Text('所在城市（可空）')
              .fontSize(13)
              .fontColor(Theme.MUTED)
            TextInput({ text: this.city, placeholder: '如 成都' })
              .height(44)
              .fontSize(14.5)
              .onChange((v: string) => {
                this.city = v;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 6 }) {
            Text('讲法')
              .fontSize(13)
              .fontColor(Theme.MUTED)
            Row({ space: 8 }) {
              this.modeChip(this.level, 'brief', '直接结论', (): void => {
                this.level = 'brief';
              })
              this.modeChip(this.level, 'detailed', '详细讲解', (): void => {
                this.level = 'detailed';
              })
            }.width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          if (this.err.length > 0) {
            Text(this.err).fontSize(13.5).fontColor(Theme.ACCENT2).width('100%')
          }

          Button(this.loading ? '起局中…' : '起局')
            .fontSize(16)
            .height(46)
            .width('100%')
            .backgroundColor(Theme.ACCENT)
            .enabled(!this.loading)
            .onClick(() => {
              this.submit();
            })

          if (this.hasChart) {
            Column({ space: 10 }) {
              Text(this.chartCaption)
                .fontSize(13)
                .fontColor(Theme.MUTED)
                .maxLines(2)

              Column({ space: 6 }) {
                ForEach(this.pairs, (p: QmPair) => {
                  Row({ space: 8 }) {
                    Text(p.k).fontSize(12).fontColor(Theme.MUTED).width(78)
                    Text(p.v).fontSize(13).fontColor(Theme.INK).layoutWeight(1)
                  }.width('100%')
                }, (p: QmPair, idx: number) => `${idx}`)
              }
              .padding(12)
              .borderRadius(10)
              .backgroundColor(Theme.SURFACE)
              .border({ width: 1, color: Theme.SOFT_LINE })
              .width('100%')
              .alignItems(HorizontalAlign.Start)

              Column({ space: 4 }) {
                Row({ space: 4 }) {
                  this.palaceCell(GRID[0][0])
                  this.palaceCell(GRID[0][1])
                  this.palaceCell(GRID[0][2])
                }.width('100%')
                Row({ space: 4 }) {
                  this.palaceCell(GRID[1][0])
                  this.palaceCell(GRID[1][1])
                  this.palaceCell(GRID[1][2])
                }.width('100%')
                Row({ space: 4 }) {
                  this.palaceCell(GRID[2][0])
                  this.palaceCell(GRID[2][1])
                  this.palaceCell(GRID[2][2])
                }.width('100%')
                Text('宫内格式：天盘干/地盘干 · 星 · 门 · 神 · 卦(方位)')
                  .fontSize(10.5)
                  .fontColor(Theme.MUTED)
              }
              .width('100%')

              if (this.patterns.length > 0) {
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  ForEach(this.patterns, (pt: QmPattern) => {
                    Text(`${pt.name}(${pt.nature})落${pt.palace}宫`)
                      .fontSize(12)
                      .fontColor(pt.nature === '吉' ? JI_COLOR : Theme.ACCENT2)
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .margin({ right: 6, bottom: 6 })
                      .borderRadius(8)
                      .backgroundColor(pt.nature === '吉' ? '#E8F7EC' : '#FFE4E6')
                  }, (pt: QmPattern, idx: number) => `${idx}`)
                }
                .width('100%')
              }

              if (this.phase === 'idle') {
                Button('流式读盘')
                  .fontSize(15)
                  .height(44)
                  .width('100%')
                  .backgroundColor(Theme.WASH)
                  .fontColor(Theme.INK)
                  .onClick(() => {
                    this.startInterpret();
                  })
              }

              if (this.phase !== 'idle') {
                StreamResult({
                  phase: this.phase,
                  think: this.think,
                  shown: this.shown,
                  err: this.phase === 'error' ? this.streamErr : '',
                  sources: [],
                  hint: '',
                  onStop: (): void => {
                    this.stopStream();
                  },
                  onRetry: (): void => {
                    this.startInterpret();
                  }
                })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          Text('起局为确定性计算不耗 AI 额度；读盘为流式解读，受每分钟 6 次与每日额度限制。')
            .fontSize(11.5)
            .fontColor(Theme.MUTED)
            .lineHeight(17)
        }
        .padding(14)
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.PAPER)
  }

  private typeOptions(): Array<SelectOption> {
    const arr: Array<SelectOption> = [];
    for (const t of this.types) {
      const o: SelectOption = { value: t };
      arr.push(o);
    }
    return arr;
  }
}
