/**
 * JSON 安全取值工具。
 * 服务端 JSON 统一按 Record<string, Object> 逐层取值，避免 ArkTS 对任意结构做直接属性访问。
 * 字段名与 docs/mobile-app/api-contract.md 保持逐字一致。
 */

export function parseObject(text: string): Record<string, Object> | null {
  try {
    const v: Object | null = JSON.parse(text);
    if (v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v)) {
      return v as Record<string, Object>;
    }
  } catch (err) {
    // 非法 JSON 按解析失败处理
  }
  return null;
}

export function jStr(o: Record<string, Object> | null, key: string, dflt: string = ''): string {
  if (o === null || o === undefined) {
    return dflt;
  }
  const v: Object | undefined = o[key];
  if (typeof v === 'string') {
    return v as string;
  }
  if (typeof v === 'number') {
    return `${v as number}`;
  }
  return dflt;
}

export function jNum(o: Record<string, Object> | null, key: string, dflt: number = 0): number {
  if (o === null || o === undefined) {
    return dflt;
  }
  const v: Object | undefined = o[key];
  if (typeof v === 'number') {
    return v as number;
  }
  if (typeof v === 'string') {
    const n: number = parseFloat(v as string);
    if (!isNaN(n)) {
      return n;
    }
  }
  return dflt;
}

export function jBool(o: Record<string, Object> | null, key: string, dflt: boolean = false): boolean {
  if (o === null || o === undefined) {
    return dflt;
  }
  const v: Object | undefined = o[key];
  if (typeof v === 'boolean') {
    return v as boolean;
  }
  return dflt;
}

export function jObj(o: Record<string, Object> | null, key: string): Record<string, Object> | null {
  if (o === null || o === undefined) {
    return null;
  }
  const v: Object | undefined = o[key];
  if (v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v)) {
    return v as Record<string, Object>;
  }
  return null;
}

export function jArr(o: Record<string, Object> | null, key: string): Array<Object> {
  if (o === null || o === undefined) {
    return [];
  }
  const v: Object | undefined = o[key];
  if (v !== null && v !== undefined && Array.isArray(v)) {
    return v as Array<Object>;
  }
  return [];
}

export function jObjAt(arr: Array<Object>, i: number): Record<string, Object> | null {
  if (i < 0 || i >= arr.length) {
    return null;
  }
  const v: Object | undefined = arr[i];
  if (v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v)) {
    return v as Record<string, Object>;
  }
  return null;
}

/**
 * 契约 §2.3：错误 detail 可能是字符串，也可能是 422 的数组（每项含 msg 字段）。
 */
export function detailText(v: Object | null | undefined): string {
  if (v === null || v === undefined) {
    return '';
  }
  if (typeof v === 'string') {
    return v as string;
  }
  if (Array.isArray(v)) {
    const arr: Array<Object> = v as Array<Object>;
    const parts: Array<string> = [];
    for (let i = 0; i < arr.length; i++) {
      const it = jObjAt(arr, i);
      if (it !== null) {
        const m = jStr(it, 'msg', '');
        if (m.length > 0) {
          parts.push(m);
        }
      }
    }
    return parts.join('；');
  }
  return '';
}

export function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}
