import { Theme } from '../common/Theme';
import { AppState } from '../common/AppState';
import { stopActiveStream } from '../common/SseClient';
import { ChartPage } from './ChartPage';
import { FortunePage } from './FortunePage';
import { AskPage } from './AskPage';
import { DreamPage } from './DreamPage';
import { QimenPage } from './QimenPage';
import { TcmPage } from './TcmPage';

class EntryDef {
  id: string = '';
  name: string = '';
  icon: string = '';
  desc: string = '';
}

/**
 * 首页 + 全局骨架：品牌头 + 当前档案状态胶囊 + 六大功能宫格 + 页脚免责声明。
 * 七屏 = 首页宫格进入的 排盘/运势/问事/解梦/奇门/中医（对齐移动端 v1 范围）。
 */
@Entry
@Component
struct Index {
  @State view: string = 'home';
  @State chartReady: boolean = AppState.shared().hasChart();
  private stack: Array<string> = new Array<string>();
  private entries: Array<EntryDef> = new Array<EntryDef>();

  aboutToAppear(): void {
    const defs: Array<string> = [
      'chart:排盘:🧭:八字 · 紫微 · 七政',
      'fortune:运势:🌤:今日 明日 本周 本月',
      'ask:问事:💬:四领域批解与追问',
      'dream:解梦:🌙:梦境流式解读',
      'qimen:奇门:🧿:起局与流式读盘',
      'tcm:中医:🌿:症状流式问诊'
    ];
    for (let i = 0; i < defs.length; i++) {
      const parts: Array<string> = defs[i].split(':');
      const e = new EntryDef();
      e.id = parts[0];
      e.name = parts[1];
      e.icon = parts[2];
      e.desc = parts[3];
      this.entries.push(e);
    }
  }

  private open(id: string): void {
    stopActiveStream();
    this.stack.push(this.view);
    this.view = id;
  }

  private goBack(): void {
    stopActiveStream();
    const prev: string | undefined = this.stack.pop();
    this.view = (prev === undefined || prev.length === 0) ? 'home' : prev;
  }

  @Builder
  entryCard(e: EntryDef) {
    Column({ space: 6 }) {
      Text(e.icon)
        .fontSize(30)
      Text(e.name)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.INK)
      Text(e.desc)
        .fontSize(11)
        .fontColor(Theme.MUTED)
        .maxLines(1)
    }
    .width('100%')
    .padding({ top: 18, bottom: 18 })
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.SURFACE)
    .border({ width: 1, color: Theme.SOFT_LINE })
    .shadow({ radius: 0, offsetX: 0, offsetY: 3, color: '#1E111111' })
    .onClick(() => {
      this.open(e.id);
    })
  }

  @Builder
  homeView() {
    Scroll() {
      Column({ space: 14 }) {
        Text('今日运程，一键可问')
          .fontSize(14)
          .fontColor(Theme.MUTED)

        Column({ space: 10 }) {
          ForEach([0, 2, 4], (rowStart: number) => {
            Row({ space: 10 }) {
              this.entryCard(this.entries[rowStart])
              this.entryCard(this.entries[rowStart + 1])
            }
            .width('100%')
          }, (rowStart: number) => `${rowStart}`)
        }
        .width('100%')

        Column({ space: 4 }) {
          Text('传统命理解释框架，不构成医疗、法律或投资建议。')
            .fontSize(11.5)
            .fontColor(Theme.MUTED)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ top: 10, bottom: 20 })
      }
      .padding(16)
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  bodyView() {
    if (this.view === 'home') {
      this.homeView()
    } else if (this.view === 'chart') {
      ChartPage({
        onBack: (): void => {
          this.goBack();
        },
        onCharted: (): void => {
          this.chartReady = true;
        }
      })
    } else if (this.view === 'fortune') {
      FortunePage({
        onBack: (): void => {
          this.goBack();
        },
        onGoChart: (): void => {
          this.open('chart');
        }
      })
    } else if (this.view === 'ask') {
      AskPage({
        onBack: (): void => {
          this.goBack();
        },
        onGoChart: (): void => {
          this.open('chart');
        }
      })
    } else if (this.view === 'dream') {
      DreamPage({
        onBack: (): void => {
          this.goBack();
        }
      })
    } else if (this.view === 'qimen') {
      QimenPage({
        onBack: (): void => {
          this.goBack();
        }
      })
    } else if (this.view === 'tcm') {
      TcmPage({
        onBack: (): void => {
          this.goBack();
        }
      })
    }
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        if (this.view !== 'home') {
          Text('←')
            .fontSize(22)
            .fontColor(Theme.INK)
            .onClick(() => {
              this.goBack();
            })
        }
        Text('看运')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
        Blank()
        Row({ space: 5 }) {
          Text('●')
            .fontSize(9)
            .fontColor(this.chartReady ? '#2F9E44' : Theme.ACCENT2)
          Text(this.chartReady ? '盘已就绪' : '未排盘')
            .fontSize(11.5)
            .fontColor(Theme.MUTED)
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(20)
        .backgroundColor(Theme.SURFACE)
        .border({ width: 1, color: Theme.SOFT_LINE })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 12 })

      Column() {
        this.bodyView()
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.PAPER)
  }
}
