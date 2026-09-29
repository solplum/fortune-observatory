import { Theme } from '../common/Theme';

/**
 * 折叠思考链（设计规格 §4.3）：
 * 思考期自动展开；正文 delta 一到自动收起，可点开回看。
 */
@Component
export struct ThinkTrace {
  @Prop @Watch('apply') think: string = '';
  @Prop @Watch('apply') phase: string = '';
  @State open: boolean = false;

  aboutToAppear(): void {
    this.apply();
  }

  apply(): void {
    if (this.phase === 'streaming' || this.phase === 'done' || this.phase === 'error') {
      this.open = false;
    } else if (this.think.length > 0) {
      this.open = true;
    }
  }

  build() {
    if (this.think.length > 0 || this.phase === 'thinking') {
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Text(this.phase === 'thinking' ? '思考中…' : '已深度推演 · 点击查看思路')
            .fontSize(13)
            .fontColor(Theme.ACCENT)
            .layoutWeight(1)
            .maxLines(1)
          Text(this.open ? '▾' : '▸')
            .fontSize(13)
            .fontColor(Theme.MUTED)
        }
        .height(44)
        .width('100%')
        .onClick(() => {
          this.open = !this.open;
        })

        if (this.open) {
          Scroll() {
            Text(this.think)
              .fontSize(13)
              .lineHeight(20)
              .fontColor(Theme.MUTED)
              .width('100%')
          }
          .height(200)
          .width('100%')
          .align(Alignment.TopStart)
          .scrollBar(BarState.Auto)
          .backgroundColor('#FAF7EC')
          .borderRadius(8)
          .padding(8)
        }
      }
      .padding({ left: 10, right: 10, top: 4, bottom: 10 })
      .borderRadius(12)
      .border({ width: 1, style: BorderStyle.Dashed, color: Theme.SOFT_LINE })
      .backgroundColor('#FFFDF4')
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
