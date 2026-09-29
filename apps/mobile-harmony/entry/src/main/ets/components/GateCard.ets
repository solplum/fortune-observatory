import { Theme } from '../common/Theme';

/**
 * 门牌卡（对齐 Web task-gate）：未排盘时引导先完成一次排盘。
 */
@Component
export struct GateCard {
  @Prop message: string = '';
  @Prop actionText: string = '去排盘';
  onAction: () => void = () => {
  };

  build() {
    Column({ space: 12 }) {
      Text('先完成一次排盘')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.INK)
      Text(this.message)
        .fontSize(14)
        .fontColor(Theme.MUTED)
        .lineHeight(21)
        .textAlign(TextAlign.Center)
      Button(this.actionText)
        .fontSize(14)
        .height(40)
        .backgroundColor(Theme.ACCENT)
        .onClick(() => {
          this.onAction();
        })
    }
    .padding(24)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.SURFACE)
    .border({ width: 1, color: Theme.SOFT_LINE })
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
