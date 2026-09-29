/**
 * 打字机节奏器（设计规格 §4.2）：
 * 流式期间恒速 80 字/秒，done/error 后加速 640 字/秒放完余量；
 * 帧间小数步长累积，防非整速率丢字。
 */
export class Pacer {
  private timer: number = -1;
  private lastMs: number = 0;
  private accT: number = 0;
  private accK: number = 0;

  fullText: string = '';
  fullThink: string = '';
  private textPos: number = 0;
  private thinkPos: number = 0;
  private inputDone: boolean = false;

  /** 每帧回调：正文已显示、思考链已显示、是否已放完 */
  onTick: (text: string, think: string, drained: boolean) => void =
    (text: string, think: string, drained: boolean) => {
    };

  appendFullText(s: string): void {
    this.fullText += s;
  }

  appendFullThink(s: string): void {
    this.fullThink += s;
  }

  markInputDone(): void {
    this.inputDone = true;
  }

  /** 重连前清空（服务端会全量回放，契约 §4.1） */
  reset(): void {
    this.fullText = '';
    this.fullThink = '';
    this.textPos = 0;
    this.thinkPos = 0;
    this.accT = 0;
    this.accK = 0;
  }

  /** 立即放完（停止流时用） */
  flush(): void {
    this.inputDone = true;
    this.textPos = this.fullText.length;
    this.thinkPos = this.fullThink.length;
    this.onTick(this.fullText, this.fullThink, true);
    this.stop();
  }

  start(): void {
    if (this.timer >= 0) {
      return;
    }
    this.lastMs = Date.now();
    this.timer = setInterval(() => {
      this.tick();
    }, 100);
  }

  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private tick(): void {
    const now = Date.now();
    const dt = (now - this.lastMs) / 1000.0;
    this.lastMs = now;
    const rate = this.inputDone ? 640.0 : 80.0;

    this.accK += rate * dt;
    const stepK = Math.floor(this.accK);
    if (stepK > 0) {
      this.accK -= stepK;
      this.thinkPos = Math.min(this.fullThink.length, this.thinkPos + stepK);
    }
    this.accT += rate * dt;
    const stepT = Math.floor(this.accT);
    if (stepT > 0) {
      this.accT -= stepT;
      this.textPos = Math.min(this.fullText.length, this.textPos + stepT);
    }

    const drainedNow = this.inputDone
      && this.textPos >= this.fullText.length
      && this.thinkPos >= this.fullThink.length;
    this.onTick(this.fullText.substring(0, this.textPos),
      this.fullThink.substring(0, this.thinkPos),
      drainedNow);
    if (drainedNow) {
      this.stop();
    }
  }
}
