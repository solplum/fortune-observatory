import { Theme } from '../common/Theme';
import { AppState } from '../common/AppState';
import { apiGet } from '../common/ApiClient';
import { parseObject, jBool } from '../common/JsonUtil';
import { Pacer } from '../common/Pacer';
import { SseEvent, SseSession, startStream, stopActiveStream } from '../common/SseClient';
import { StreamResult } from '../components/StreamResult';
import { GateCard } from '../components/GateCard';

interface ReadingBody {
  question: string;
  split_questions: Array<string>;
  context_tokens: Array<string>;
  history: Array<Object>;
  stream_key: string;
}

class DomainDef {
  key: string = '';      // ai_contexts key
  label: string = '';
}

/**
 * 问事页：四领域批解（健康/姻缘/事业/财运）+ 自由问题 → POST /v1/ai/reading（SSE）。
 * 领域 token + ziwei token 组合上下文（契约 §4.2，对齐 Web DomainAnalysisConsole 口径）。
 */
@Component
export struct AskPage {
  onBack: () => void = () => {
  };
  onGoChart: () => void = () => {
  };

  @State domain: string = 'career';
  @State question: string = '';
  @State phase: string = 'idle';
  @State think: string = '';
  @State shown: string = '';
  @State err: string = '';
  @State hint: string = '';
  private domains: Array<DomainDef> = new Array<DomainDef>();
  private pacer: Pacer = new Pacer();
  private session: SseSession | null = null;
  /** 当前问事的续传键：重试必须携带同一 stream_key 才能命中服务端回放（契约 §4.1/§8.4） */
  private streamKey: string = '';

  aboutToAppear(): void {
    const defs: Array<string> = ['health:健康', 'relationship:姻缘', 'career:事业', 'wealth:财运'];
    for (let i = 0; i < defs.length; i++) {
      const sep: number = defs[i].indexOf(':');
      const d = new DomainDef();
      d.key = defs[i].substring(0, sep);
      d.label = defs[i].substring(sep + 1);
      this.domains.push(d);
    }
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

  private domainLabel(): string {
    for (let i = 0; i < this.domains.length; i++) {
      if (this.domains[i].key === this.domain) {
        return this.domains[i].label;
      }
    }
    return this.domain;
  }

  private buildRequestBody(reuseKey: boolean): string | null {
    const app = AppState.shared();
    const dTok: string = app.contextToken(this.domain);
    const zTok: string = app.contextToken('ziwei');
    const tokens: Array<string> = [];
    if (dTok.length > 0) {
      tokens.push(dTok);
    }
    if (zTok.length > 0 && zTok !== dTok) {
      tokens.push(zTok);
    }
    if (tokens.length === 0) {
      return null;
    }
    let q: string = this.question.trim();
    if (q.length === 0) {
      q = `请结合命盘，详细批解我的${this.domainLabel()}。`;
    }
    if (!reuseKey || this.streamKey.length === 0) {
      this.streamKey = `ask-${this.domain}-${Date.now()}`;
    }
    const body: ReadingBody = {
      question: q,
      split_questions: [],
      context_tokens: tokens,
      history: [],
      stream_key: this.streamKey
    };
    return JSON.stringify(body);
  }

  private probeStatus(): void {
    apiGet('/v1/ai/status', 6000).then((r) => {
      if (r.ok) {
        const obj = parseObject(r.body);
        const available: boolean = obj !== null && jBool(obj, 'available', false);
        if (available) {
          this.hint = 'AI 服务可用，但这次排盘没有携带解读上下文（token 缺失或已过期 30 分钟）。请回到「排盘」重新生成命盘后再来问事。';
        } else {
          this.hint = '服务端 AI 讲解暂未配置，规则结果仍可正常使用。';
        }
      } else {
        this.hint = `无法确认 AI 服务状态：${r.error}`;
      }
    });
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
        // 契约 §8.6：安全红线时正文不可信，清空已展示文本
        this.pacer.reset();
        this.shown = '';
        this.think = '';
      }
      this.err = evt.detail.length > 0 ? evt.detail : '解读失败，请稍后重试。';
      this.phase = 'error';
    }
  }

  /**
   * @param reuseKey true=重试（携带同一 stream_key 命中服务端续传回放）；false=新问题（新会话）
   */
  private start(reuseKey: boolean): void {
    const body: string | null = this.buildRequestBody(reuseKey);
    if (body === null) {
      this.hint = '';
      this.probeStatus();
      return;
    }
    if (this.question.trim().length > 300) {
      this.err = '问题最长 300 字。';
      return;
    }
    this.err = '';
    this.hint = '';
    this.pacer.reset();
    this.shown = '';
    this.think = '';
    this.phase = 'connecting';
    const self = this;
    this.session = startStream('/v1/ai/reading', body, {
      onEvent: (evt: SseEvent): void => {
        self.handleEvent(evt);
      },
      onReset: (): void => {
        // 服务端重连会全量回放：清空本地缓冲
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
        Text('问事')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 6 })

      if (!AppState.shared().hasChart()) {
        Column() {
          GateCard({
            message: '问事按你的命盘作答。先完成一次排盘，再选领域提问。',
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
              ForEach(this.domains, (d: DomainDef) => {
                Text(d.label)
                  .fontSize(13.5)
                  .fontColor(this.domain === d.key ? Theme.INK : Theme.MUTED)
                  .textAlign(TextAlign.Center)
                  .height(36)
                  .layoutWeight(1)
                  .borderRadius(9)
                  .backgroundColor(this.domain === d.key ? Theme.WASH : Theme.SURFACE)
                  .border({ width: 1, color: this.domain === d.key ? Theme.LINE : Theme.SOFT_LINE })
                  .onClick(() => {
                    this.domain = d.key;
                  })
              }, (d: DomainDef, idx: number) => `${idx}`)
            }.width('100%')

            Column({ space: 6 }) {
              Text(`想问什么？（可留空，默认批解${this.domainLabel()}；最长 300 字）`)
                .fontSize(13)
                .fontColor(Theme.MUTED)
              TextArea({ text: this.question, placeholder: `例如：今年下半年适合换工作吗？` })
                .height(88)
                .fontSize(14.5)
                .onChange((v: string) => {
                  this.question = v;
                })
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
                  this.start(false);
                })
            }

            if (this.phase === 'idle' && this.hint.length > 0) {
              // token 缺失/过期引导（契约 §8.7/§8.8）：idle 态下 StreamResult 不挂载，需独立渲染
              Text(this.hint)
                .fontSize(13)
                .fontColor(Theme.ACCENT2)
                .lineHeight(19)
                .width('100%')
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
                sources: [],
                hint: this.hint,
                onStop: (): void => {
                  this.stop();
                },
                onRetry: (): void => {
                  this.start(true);
                }
              })
            }

            Text('解读结合盘面事实生成；上下文 token 有效期 30 分钟，过期请重新排盘。内容为传统命理解释框架，不构成专业建议。')
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.PAPER)
  }
}
