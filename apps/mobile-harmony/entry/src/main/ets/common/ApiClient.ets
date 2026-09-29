import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { parseObject, detailText } from './JsonUtil';

/**
 * API 基址统一收敛于此（契约 §0）：https://destiny.solplum.com/api
 * 生产只认该 Host（TrustedHostMiddleware），不得做备用直连地址。
 */
export const BASE_URL: string = 'https://destiny.solplum.com/api';

export class ApiResult {
  ok: boolean = false;
  status: number = 0;
  body: string = '';
  error: string = '';
  /** 429 时服务端 Retry-After 秒数（无该头为 0）。 */
  retryAfterSeconds: number = 0;
}

function jsonHeaders(): Record<string, string> {
  const h: Record<string, string> = {
    'accept': 'application/json',
    'content-type': 'application/json'
  };
  return h;
}

/** 读响应头里 Retry-After 的秒数（键大小写不敏感；无头/非法值返回 0）。 */
function retryAfterSeconds(header: Object): number {
  if (header === null || header === undefined) {
    return 0;
  }
  const rec = header as Record<string, Object>;
  const keys = Object.keys(rec);
  for (let i = 0; i < keys.length; i++) {
    if (keys[i].toLowerCase() === 'retry-after') {
      const n = parseInt(`${rec[keys[i]]}`, 10);
      return Number.isNaN(n) || n < 0 ? 0 : n;
    }
  }
  return 0;
}

async function request(method: http.RequestMethod, path: string, body: string, timeoutMs: number): Promise<ApiResult> {
  const client = http.createHttp();
  const result = new ApiResult();
  let opt: http.HttpRequestOptions;
  if (body.length > 0) {
    opt = {
      method: method,
      header: jsonHeaders(),
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: timeoutMs
    };
  } else {
    opt = {
      method: method,
      header: jsonHeaders(),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: timeoutMs
    };
  }
  try {
    const resp = await client.request(BASE_URL + path, opt);
    result.status = resp.responseCode;
    result.body = resp.result as string;
    result.ok = resp.responseCode >= 200 && resp.responseCode < 300;
    if (!result.ok) {
      // 契约 §2.3：detail 可能是字符串或 422 数组，原文案透出给用户
      const parsed = parseObject(result.body);
      if (parsed !== null) {
        const d = detailText(parsed['detail']);
        if (d.length > 0) {
          result.error = d;
        }
      }
      if (result.error.length === 0) {
        result.error = `请求失败（HTTP ${resp.responseCode}）`;
      }
      if (resp.responseCode === 429) {
        // 契约 §2.1/§8.2：429 解析 Retry-After，秒数写进文案（SSE 路径因 requestInStream 无响应头，给静态提示）
        const ra = retryAfterSeconds(resp.header);
        if (ra > 0) {
          result.retryAfterSeconds = ra;
          result.error = `${result.error}（${ra}秒后再试）`;
        }
      }
    }
  } catch (err) {
    const be = err as BusinessError;
    result.error = `网络请求失败：${be.message}`;
  } finally {
    client.destroy();
  }
  return result;
}

export async function apiPost(path: string, body: string, timeoutMs: number): Promise<ApiResult> {
  return request(http.RequestMethod.POST, path, body, timeoutMs);
}

export async function apiGet(path: string, timeoutMs: number): Promise<ApiResult> {
  return request(http.RequestMethod.GET, path, '', timeoutMs);
}
