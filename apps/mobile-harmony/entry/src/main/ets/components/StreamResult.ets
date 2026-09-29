import { Theme } from '../common/Theme';
import { MarkdownBody } from './MarkdownBody';
import { ThinkTrace } from './ThinkTrace';

/**
 * 流式结果通用面板：进度行 + 折叠思考链 + 打字机正文 + 错误卡 + 引用列表。
 * phase: idle | connecting | thinking | streaming | done | error
 */
@Component
export struct StreamResult {
  @Prop phase: string = 'idle';
  @Prop think: string = '';
  @Prop shown: string = '';
  @Prop err: string = '';
  @Prop sources: Array<string> = new Array<string>();
  @Prop hint: string = '';
  onStop: () => void = () => {
  };
  onRetry: () => void = () => {
  };

  build() {
    Column({ space: 12 }) {
      if (this.phase === 'connecting' || this.phase === 'thinking' || this.phase === 'streaming') {
        Row({ space: 10 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(Theme.ACCENT)
          Text(this.phase === 'connecting' ? '正在连接…' :
            (this.phase === 'thinking' ? '思考中…' : '正在输出…'))
            .fontSize(14)
            .fontColor(Theme.MUTED)
            .layoutWeight(1)
          Button('停止')
            .fontSize(13)
            .height(32)
            .backgroundColor(Theme.SURFACE)
            .fontColor(Theme.INK)
            .border({ width: 1, color: Theme.LINE })
            .onClick(() => {
              this.onStop();
            })
        }
        .width('100%')
        .padding(10)
        .borderRadius(12)
        .backgroundColor(Theme.SURFACE)
        .border({ width: 1, color: Theme.SOFT_LINE })
      }

      ThinkTrace({ think: this.think, phase: this.phase })

      if (this.shown.length > 0) {
        Column({ space: 10 }) {
          MarkdownBody({ text: this.shown })
        }
        .padding(14)
        .borderRadius(Theme.RADIUS)
        .backgroundColor(Theme.SURFACE)
        .border({ width: 1, color: Theme.SOFT_LINE })
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      if (this.err.length > 0) {
        Column({ space: 8 }) {
          Text(this.err)
            .fontSize(14)
            .fontColor(Theme.ACCENT2)
            .lineHeight(21)
            .width('100%')
          Button('重试')
            .fontSize(13)
            .height(34)
            .backgroundColor(Theme.SURFACE)
            .fontColor(Theme.ACCENT)
            .border({ width: 1, color: Theme.ACCENT })
            .onClick(() => {
              this.onRetry();
            })
        }
        .padding(12)
        .borderRadius(12)
        .backgroundColor('#FFF1F2')
        .border({ width: 1, color: '#33FF3044' })
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      if (this.sources.length > 0) {
        Column({ space: 6 }) {
          Text('口径与出处')
            .fontSize(13)
            .fontColor(Theme.MUTED)
          ForEach(this.sources, (s: string) => {
            Text(s)
              .fontSize(12.5)
              .lineHeight(19)
              .fontColor(Theme.INK)
              .width('100%')
          }, (s: string, idx: number) => `${idx}|${s}`)
        }
        .padding(12)
        .borderRadius(12)
        .backgroundColor(Theme.SURFACE)
        .border({ width: 1, color: Theme.SOFT_LINE })
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(12)
          .fontColor(Theme.MUTED)
          .lineHeight(18)
          .width('100%')
      }
    }
    .width('100%')
  }
}
