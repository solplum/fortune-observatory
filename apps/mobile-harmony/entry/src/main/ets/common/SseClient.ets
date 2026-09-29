import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { BASE_URL } from './ApiClient';
import { parseObject, jArr, jObjAt, jStr, detailText } from './JsonUtil';

/**
 * SSE 流式客户端（契约 §4.1-§4.6）：
 * - @ohos.net.http requestInStream 分块接收，TextDecoder stream 模式处理跨 chunk 截断的多字节字符；
 * - 行解析：':' 开头注释行（心跳）忽略；'data: [DONE]' 哨兵行忽略；'data: {JSON}' 解析为事件；
 * - 两种终态并存：reading 以 {"type":"done"} 收尾、无哨兵；解梦/奇门/中医 done 后还有 data: [DONE]——
 *   统一按「忽略哨兵 + 以 done/error 事件定终态」兼容；
 * - 断线续传：静默断流 → 清空本地缓冲（onReset，服务端会全量回放）→ 600ms 后重连 → 最多 2 次；
 * - 全进程单例流：新流启动前销毁旧流，规避同 IP 在途 2 条的连接帽（契约 §8.14）。
 */

export class SseSource {
  work: string = '';
  quote: string = '';
  channel: string = '';
}

export class SseEvent {
  type: string = '';
  text: string = '';
  detail: string = '';
  code: string = '';
  sources: Array<SseSource> = new Array<SseSource>();
}

export interface SseCallbacks {
  /** 收到一条 data 事件（think/delta/done/error） */
  onEvent: (evt: SseEvent) => void;
  /** 每次重连前回调：调用方应清空本地缓冲，等服务端全量回放 */
  onReset: () => void;
  /** 传输层重连次数用尽（一般已通过 onEvent 下发 error，此回调供调用方兜底） */
  onFatal: () => void;
}

function sseHeaders(): Record<string, string> {
  const h: Record<string, string> = {
    'accept': 'text/event-stream',
    'content-type': 'application/json'
  };
  return h;
}

const MAX_RETRIES: number = 2;
const RECONNECT_DELAY_MS: number = 600;
const READ_TIMEOUT_MS: number = 30000; // 服务端心跳 10s 一次，30s 读超时留足余量

export class SseSession {
  private path: string;
  private body: string;
  private cb: SseCallbacks;
  private req: http.HttpRequest | null = null;
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private lineBuf: string = '';
  private otherBuf: string = '';
  private attempts: number = 0;
  private stopped: boolean = false;
  private terminal: boolean = false;
  private sawData: boolean = false;
  private statusCode: number = 0;
  private reconnectTimer: number = -1;

  constructor(path: string, body: string, cb: SseCallbacks) {
    this.path = path;
    this.body = body;
    this.cb = cb;
  }

  start(): void {
    this.attempts = 0;
    this.spawn();
  }

  stop(): void {
    this.stopped = true;
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    this.closeReq();
  }

  private closeReq(): void {
    if (this.req !== null) {
      try {
        this.req.destroy();
      } catch (err) {
        // 忽略销毁异常
      }
      this.req = null;
    }
  }

  private async spawn(): Promise<void> {
    if (this.stopped || this.terminal) {
      return;
    }
    this.closeReq();
    this.lineBuf = '';
    this.otherBuf = '';
    this.sawData = false;
    this.statusCode = 0;

    const client = http.createHttp();
    this.req = client;
    client.on('dataReceive', (chunk: ArrayBuffer) => {
      this.onChunk(chunk);
    });
    client.on('dataEnd', () => {
      this.onEnd();
    });
    const opt: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: sseHeaders(),
      extraData: this.body,
      connectTimeout: 10000,
      readTimeout: READ_TIMEOUT_MS
    };
    try {
      const code: number = await client.requestInStream(BASE_URL + this.path, opt);
      this.statusCode = code;
    } catch (err) {
      const be = err as BusinessError;
      // 连接层失败：按静默断流走重连
      this.handleDisconnect(`连接失败：${be.message}`);
    }
  }

  private onChunk(chunk: ArrayBuffer): void {
    if (this.stopped || this.terminal) {
      return;
    }
    if (chunk === null || chunk === undefined || chunk.byteLength === 0) {
      return;
    }
    const bytes: Uint8Array = new Uint8Array(chunk);
    let piece: string = '';
    try {
      // stream: true —— 保留跨 chunk 的不完整 UTF-8 序列
      piece = this.decoder.decodeWithStream(bytes, { stream: true });
    } catch (err) {
      piece = '';
    }
    if (piece.length === 0) {
      return;
    }
    this.lineBuf += piece;
    let idx: number = this.lineBuf.indexOf('\n');
    while (idx >= 0) {
      const line: string = this.lineBuf.substring(0, idx);
      this.lineBuf = this.lineBuf.substring(idx + 1);
      this.handleLine(line);
      if (this.stopped || this.terminal) {
        return;
      }
      idx = this.lineBuf.indexOf('\n');
    }
  }

  private handleLine(raw: string): void {
    let line: string = raw;
    if (line.endsWith('\r')) {
      line = line.substring(0, line.length - 1);
    }
    if (line.length === 0) {
      return;
    }
    if (line.startsWith(':')) {
      return; // 心跳注释行：': ping' 或 ': ' + 200 个 k
    }
    if (!line.startsWith('data:')) {
      // 非 SSE 行：多半是非流式错误响应的 JSON（429/413/422 等）
      this.otherBuf += line + '\n';
      return;
    }
    let payload: string = line.substring(5);
    if (payload.startsWith(' ')) {
      payload = payload.substring(1);
    }
    this.sawData = true;
    if (payload === '[DONE]') {
      return; // 哨兵行：终态已由 done/error 事件给出
    }
    const obj = parseObject(payload);
    if (obj === null) {
      return;
    }
    const evt = new SseEvent();
    evt.type = jStr(obj, 'type', '');
    evt.text = jStr(obj, 'text', '');
    evt.detail = jStr(obj, 'detail', '');
    evt.code = jStr(obj, 'code', '');
    const srcArr: Array<Object> = jArr(obj, 'sources');
    for (let i = 0; i < srcArr.length; i++) {
      const so = jObjAt(srcArr, i);
      if (so === null) {
        continue;
      }
      const s = new SseSource();
      s.work = jStr(so, 'work', '');
      s.quote = jStr(so, 'quote', '');
      s.channel = jStr(so, 'channel', '');
      evt.sources.push(s);
    }
    if (evt.type === 'done' || evt.type === 'error') {
      this.terminal = true;
    }
    this.cb.onEvent(evt);
  }

  private onEnd(): void {
    if (this.stopped) {
      this.closeReq();
      return;
    }
    if (this.terminal) {
      this.closeReq();
      return;
    }
    if (this.sawData) {
      // 收到过事件但流被掐断：静默断流 → 清缓冲重连（服务端回放）
      this.handleDisconnect('');
      return;
    }
    // 没有任何 SSE data：大概率是非流式错误响应（限流/校验失败）
    const obj = parseObject(this.otherBuf);
    if (obj !== null) {
      // 契约 §2.3：detail 可能是字符串或 [{msg}] 数组，统一走 detailText（与 ApiClient 同一解析姿势）
      let d = detailText(obj['detail']);
      if (this.statusCode === 429) {
        // requestInStream 不回传响应头、取不到 Retry-After：按契约限流窗 6/min 给静态等待提示
        d = `${d.length > 0 ? d : '触发限流'}（请约 10 秒后再试）`;
      }
      const evt = new SseEvent();
      evt.type = 'error';
      evt.detail = d.length > 0 ? d : `服务返回异常（HTTP ${this.statusCode}）`;
      this.terminal = true;
      this.cb.onEvent(evt);
      this.closeReq();
      return;
    }
    this.handleDisconnect('');
    this.closeReq();
  }

  private handleDisconnect(reason: string): void {
    if (this.stopped || this.terminal) {
      return;
    }
    this.closeReq();
    if (this.attempts >= MAX_RETRIES) {
      this.terminal = true;
      const evt = new SseEvent();
      evt.type = 'error';
      evt.detail = reason.length > 0 ? reason : '连接中断，自动重连仍未恢复，请重试。';
      this.cb.onEvent(evt);
      this.cb.onFatal();
      return;
    }
    this.attempts += 1;
    this.cb.onReset();
    const self = this;
    this.reconnectTimer = setTimeout(() => {
      self.reconnectTimer = -1;
      self.spawn();
    }, RECONNECT_DELAY_MS);
  }
}

// 进程内单例流：同 IP 在途流帽为 2，切页/发起新流前必须收掉旧流
let active: SseSession | null = null;

export function stopActiveStream(): void {
  if (active !== null) {
    active.stop();
    active = null;
  }
}

export function hasActiveStream(): boolean {
  return active !== null;
}

export function startStream(path: string, body: string, cb: SseCallbacks): SseSession {
  stopActiveStream();
  const s = new SseSession(path, body, cb);
  active = s;
  s.start();
  return s;
}
