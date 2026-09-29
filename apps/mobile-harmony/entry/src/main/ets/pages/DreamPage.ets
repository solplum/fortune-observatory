import { Theme } from '../common/Theme';
import { Pacer } from '../common/Pacer';
import { SseEvent, SseSession, startStream, stopActiveStream } from '../common/SseClient';
import { StreamResult } from '../components/StreamResult';

interface DreamBody {
  dream: string;
}

/**
 * 解梦页：梦境文本 → POST /v1/dreams/interpret/stream（SSE）。
 * done 事件带 sources（work/quote/channel，channel ∈ 字面|近邻）；断线重试原样重发 body（服务端按 body 哈希续传）。
 */
@Component
export struct DreamPage {
  onBack: () => void = () => {
  };

  @State dream: string = '';
  @State phase: string = 'idle';
  @State think: string = '';
  @State shown: string = '';
  @State err: string = '';
  @State sources: Array<string> = new Array<string>();
  private pacer: Pacer = new Pacer();
  private session: SseSession | null = null;

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
      const parts: Array<string> = [];
      for (let i = 0; i < evt.sources.length; i++) {
        const s = evt.sources[i];
        const channel: string = s.channel.length > 0 ? `（${s.channel}）` : '';
        parts.push(`《${s.work}》 ${s.quote}${channel}`);
      }
      this.sources = parts;
      this.pacer.markInputDone();
      this.phase = 'done';
    } else if (evt.type === 'error') {
      this.pacer.markInputDone();
      if (evt.code === 'safety') {
        this.pacer.reset();
        this.shown = '';
        this.think = '';
      }
      this.err = evt.detail.length > 0 ? evt.detail : '解梦失败，请稍后重试。';
      this.phase = 'error';
    }
  }

  private start(): void {
    const text: string = this.dream.trim();
    if (text.length < 4) {
      this.err = '梦境描述至少 4 个字。';
      return;
    }
    if (text.length > 2000) {
      this.err = '梦境描述最长 2000 字。';
      return;
    }
    this.err = '';
    this.sources = [];
    this.pacer.reset();
    this.shown = '';
    this.think = '';
    this.phase = 'connecting';
    const body: DreamBody = { dream: text };
    const bodyStr: string = JSON.stringify(body);
    const self = this;
    this.session = startStream('/v1/dreams/interpret/stream', bodyStr, {
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

  private stop(): void {
    stopActiveStream();
    this.pacer.markInputDone();
    this.phase = 'done';
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
        Text('解梦')
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
            Text('梦见了什么？（4-2000 字）')
              .fontSize(13)
              .fontColor(Theme.MUTED)
            TextArea({ text: this.dream, placeholder: '例如：梦见一条蛇钻进怀里' })
              .height(96)
              .fontSize(14.5)
              .maxLength(2000)
              .onChange((v: string) => {
                this.dream = v;
              })
            Row({ space: 8 }) {
              Text('试试：')
                .fontSize(12)
                .fontColor(Theme.MUTED)
              ForEach(['掉牙', '飞翔', '被追赶'], (s: string) => {
                Text(s)
                  .fontSize(12)
                  .fontColor(Theme.ACCENT)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(8)
                  .backgroundColor(Theme.SURFACE)
                  .border({ width: 1, color: Theme.SOFT_LINE })
                  .onClick(() => {
                    this.dream = `梦见${s}`;
                  })
              }, (s: string, idx: number) => `${idx}`)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          if (this.phase === 'idle') {
            Button('开始解读')
              .fontSize(16)
              .height(46)
              .width('100%')
              .backgroundColor(Theme.ACCENT)
              .onClick(() => {
                this.start();
              })
          }

          if (this.err.length > 0 && this.phase !== 'error') {
            Text(this.err).fontSize(13.5).fontColor(Theme.ACCENT2).width('100%')
          }

          if (this.phase !== 'idle') {
            StreamResult({
              phase: this.phase,
              think: this.think,
              shown: this.shown,
              err: this.phase === 'error' ? this.err : '',
              sources: this.sources,
              hint: '',
              onStop: (): void => {
                this.stop();
              },
              onRetry: (): void => {
                this.start();
              }
            })
          }

          Text('解读口径取自经典梦学著作；急症与自伤情形会直接给出去专业求助的转介说明。')
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
}
