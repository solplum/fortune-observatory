import { Theme } from '../common/Theme';

class MdBlock {
  kind: string = 'p'; // h=小节标题 li=列表 p=段落
  text: string = '';
}

class MdSeg {
  text: string = '';
  bold: boolean = false;
}

/**
 * 行内富文本：**加粗** 转 Span 加粗；
 * 流式尾部奇数个 ** 时末段按加粗渲染防闪烁（设计规格 §4.2）。
 */
@Component
export struct RichLine {
  @Prop src: string = '';
  @Prop baseSize: number = 15;

  private segs(s: string): Array<MdSeg> {
    const parts: Array<MdSeg> = [];
    const pieces: Array<string> = s.split('**');
    const unclosedBold: boolean = pieces.length % 2 === 0 && pieces.length > 1;
    for (let i = 0; i < pieces.length; i++) {
      if (pieces[i].length === 0) {
        continue;
      }
      const seg = new MdSeg();
      seg.text = pieces[i];
      seg.bold = (i % 2 === 1) || (unclosedBold && i === pieces.length - 1);
      parts.push(seg);
    }
    return parts;
  }

  build() {
    Text() {
      ForEach(this.segs(this.src), (s: MdSeg) => {
        Span(s.text)
          .fontWeight(s.bold ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(s.bold ? Theme.INK : Theme.INK)
      }, (s: MdSeg, idx: number) => `${idx}|${s.text}`)
    }
    .fontSize(this.baseSize)
    .lineHeight(this.baseSize * 1.65)
    .fontColor(Theme.INK)
    .width('100%')
  }
}

/**
 * Markdown-lite 渲染（设计规格 §4.2 / 契约 §8.10）：
 * 空行分段；# 行转小节标题；连续列表行转圆点；--- 忽略；
 * 正文是自由 Markdown 非 JSON，禁止按富文本/JSON 解析。
 */
@Component
export struct MarkdownBody {
  @Prop text: string = '';
  @Prop baseSize: number = 15;

  private blocks(src: string): Array<MdBlock> {
    const list: Array<MdBlock> = [];
    const lines: Array<string> = src.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      if (line === '---' || line === '***') {
        continue;
      }
      const b = new MdBlock();
      if (line.startsWith('###')) {
        b.kind = 'h';
        b.text = line.substring(3).trim();
      } else if (line.startsWith('##')) {
        b.kind = 'h';
        b.text = line.substring(2).trim();
      } else if (line.startsWith('#')) {
        b.kind = 'h';
        b.text = line.substring(1).trim();
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        b.kind = 'li';
        b.text = line.substring(2).trim();
      } else {
        b.kind = 'p';
        b.text = line;
      }
      if (b.text.length > 0) {
        list.push(b);
      }
    }
    return list;
  }

  private stripBold(s: string): string {
    return s.split('**').join('');
  }

  build() {
    Column({ space: 8 }) {
      ForEach(this.blocks(this.text), (b: MdBlock) => {
        if (b.kind === 'h') {
          Text(this.stripBold(b.text))
            .fontSize(this.baseSize + 2)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.ACCENT)
            .width('100%')
            .textAlign(TextAlign.Start)
        } else if (b.kind === 'li') {
          Row({ space: 6 }) {
            Text('·')
              .fontSize(this.baseSize + 2)
              .fontColor(Theme.ACCENT2)
              .fontWeight(FontWeight.Bold)
            RichLine({ src: b.text, baseSize: this.baseSize })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else if (b.text.startsWith('【免责声明】')) {
          // 中医免责框（契约 §4.6）：后端强保证收尾，原样渲染、不截断
          Text(this.stripBold(b.text))
            .fontSize(this.baseSize - 1)
            .fontColor(Theme.MUTED)
            .lineHeight((this.baseSize - 1) * 1.6)
            .padding(10)
            .borderRadius(10)
            .backgroundColor('#FFF6DE')
            .width('100%')
        } else {
          RichLine({ src: b.text, baseSize: this.baseSize })
        }
      }, (b: MdBlock, idx: number) => `${idx}|${b.kind}|${b.text.length}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
