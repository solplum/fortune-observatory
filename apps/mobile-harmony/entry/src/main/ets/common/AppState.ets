import { parseObject, jObj, jStr } from './JsonUtil';

/**
 * 进程级应用状态：当前出生档案 + 最近一次排盘/起局的原始 JSON。
 * v1 明确不做本地持久化（无偏好存储），进程存活期内有效。
 */
export class AppState {
  private static inst: AppState | null = null;

  static shared(): AppState {
    if (AppState.inst === null) {
      AppState.inst = new AppState();
    }
    return AppState.inst;
  }

  /** BirthInput 请求体原样字符串（发运势/问事时原样嵌入 body，保证逐字节一致） */
  birthJson: string = '';
  /** 档案摘要，用于展示 */
  birthLabel: string = '';
  /** POST /v1/charts 响应原文 */
  chartJson: string = '';
  /** POST /v1/qimen/chart 响应原文（奇门解读要求整盘原样回传） */
  qimenJson: string = '';

  hasChart(): boolean {
    return this.chartJson.length > 0;
  }

  hasQimen(): boolean {
    return this.qimenJson.length > 0;
  }

  chart(): Record<string, Object> | null {
    return parseObject(this.chartJson);
  }

  /**
   * ai_contexts：key ∈ health|relationship|career|wealth|ziwei|bazi|qizheng。
   * 契约 §3.1：服务端未配 secret 或未核验时整包为空对象，客户端必须容忍缺 key。
   */
  chartContexts(): Record<string, Object> | null {
    const c = this.chart();
    if (c === null) {
      return null;
    }
    return jObj(c, 'ai_contexts');
  }

  contextToken(key: string): string {
    const ctx = this.chartContexts();
    if (ctx === null) {
      return '';
    }
    const bundle = jObj(ctx, key);
    if (bundle === null) {
      return '';
    }
    return jStr(bundle, 'token', '');
  }

  setChart(raw: string, birthJson: string, label: string): void {
    this.chartJson = raw;
    this.birthJson = birthJson;
    this.birthLabel = label;
  }

  setQimen(raw: string): void {
    this.qimenJson = raw;
  }
}
