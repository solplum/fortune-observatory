import { Theme } from '../common/Theme';
import { Pacer } from '../common/Pacer';
import { SseEvent, SseSession, startStream, stopActiveStream } from '../common/SseClient';
import { StreamResult } from '../components/StreamResult';

interface TcmBody {
  question: string;
}

/**
 * 中医问诊页：症状输入 → POST /v1/tcm/consult/stream（SSE）。
 * 服务端强制免责框收尾（缺失会补一条 delta），客户端原样渲染、不截断（契约 §4.6）；
 * done 事件 sources 只有 work/quote 两个字段（与解梦不同，无 channel）。
 */
@Component
export struct TcmPage {
  onBack: () => void = () => {
  };

  @State question: string = '';
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
        parts.push(`《${s.work}》 ${s.quote}`);
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
      this.err = evt.detail.length > 0 ? evt.detail : '问诊失败，请稍后重试。';
      this.phase = 'error';
    }
  }

  private start(): void {
    const text: string = this.question.trim();
    if (text.length < 4) {
      this.err = '症状描述至少 4 个字。';
      return;
    }
    if (text.length > 2000) {
      this.err = '症状描述最长 2000 字。';
      return;
    }
    this.err = '';
    this.sources = [];
    this.pacer.reset();
    this.shown = '';
    this.think = '';
    this.phase = 'connecting';
    const body: TcmBody = { question: text };
    const bodyStr: string = JSON.stringify(body);
    const self = this;
    this.session = startStream('/v1/tcm/consult/stream', bodyStr, {
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
        Text('中医问诊')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 6 })

      Scroll() {
        Column({ space: 12 }) {
          Text('仅供学习，不适请就医。')
            .fontSize(12.5)
            .fontColor(Theme.ACCENT2)
            .width('100%')

          Column({ space: 6 }) {
            Text('哪里不舒服？（4-2000 字）')
              .fontSize(13)
              .fontColor(Theme.MUTED)
            TextArea({ text: this.question, placeholder: '例如：长期失眠多梦怎么办' })
              .height(96)
              .fontSize(14.5)
              .maxLength(2000)
              .onChange((v: string) => {
                this.question = v;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          if (this.phase === 'idle') {
            Button('开始问诊')
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

          Text('急症情形（含自伤信号）不走模型，直接返回转介文案；解读末尾的免责声明为服务端强制内容，请完整阅读。')
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
