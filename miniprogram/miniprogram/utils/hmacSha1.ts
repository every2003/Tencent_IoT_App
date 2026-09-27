// 纯 JS 实现 HMAC-SHA1 + Base64
// 小程序里没有 Web Crypto，第三方 crypto-js 在 npm 包外引用不便，
// 这里给一个零依赖、最小可用版本。
//
// 接口：hmacSha1Base64(key, message) => string

function _utf8Encode(str: string): number[] {
  const out: number[] = [];
  for (let i = 0; i < str.length; i++) {
    let c = str.charCodeAt(i);
    if (c < 0x80) {
      out.push(c);
    } else if (c < 0x800) {
      out.push(0xc0 | (c >> 6));
      out.push(0x80 | (c & 0x3f));
    } else if (c < 0xd800 || c >= 0xe000) {
      out.push(0xe0 | (c >> 12));
      out.push(0x80 | ((c >> 6) & 0x3f));
      out.push(0x80 | (c & 0x3f));
    } else {
      // surrogate pair
      i++;
      const cp = 0x10000 + (((c & 0x3ff) << 10) | (str.charCodeAt(i) & 0x3ff));
      out.push(0xf0 | (cp >> 18));
      out.push(0x80 | ((cp >> 12) & 0x3f));
      out.push(0x80 | ((cp >> 6) & 0x3f));
      out.push(0x80 | (cp & 0x3f));
    }
  }
  return out;
}

function _rotl(n: number, b: number): number {
  return ((n << b) | (n >>> (32 - b))) >>> 0;
}

/** SHA-1，输入字节数组，输出 20 字节 */
function _sha1(bytes: number[]): number[] {
  const len = bytes.length;
  const blocks: number[] = bytes.slice();
  blocks.push(0x80);
  while ((blocks.length % 64) !== 56) blocks.push(0);

  // 64-bit length，big-endian
  const bitLenHigh = Math.floor((len * 8) / 0x100000000);
  const bitLenLow = (len * 8) >>> 0;
  blocks.push((bitLenHigh >>> 24) & 0xff, (bitLenHigh >>> 16) & 0xff, (bitLenHigh >>> 8) & 0xff, bitLenHigh & 0xff);
  blocks.push((bitLenLow >>> 24) & 0xff, (bitLenLow >>> 16) & 0xff, (bitLenLow >>> 8) & 0xff, bitLenLow & 0xff);

  let h0 = 0x67452301;
  let h1 = 0xefcdab89;
  let h2 = 0x98badcfe;
  let h3 = 0x10325476;
  let h4 = 0xc3d2e1f0;

  const w = new Array<number>(80);

  for (let i = 0; i < blocks.length; i += 64) {
    for (let j = 0; j < 16; j++) {
      const k = i + j * 4;
      w[j] = ((blocks[k] << 24) | (blocks[k + 1] << 16) | (blocks[k + 2] << 8) | blocks[k + 3]) >>> 0;
    }
    for (let j = 16; j < 80; j++) {
      w[j] = _rotl(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);
    }

    let a = h0, b = h1, c = h2, d = h3, e = h4;
    for (let j = 0; j < 80; j++) {
      let f: number;
      let k: number;
      if (j < 20) { f = (b & c) | ((~b) & d); k = 0x5a827999; }
      else if (j < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
      else if (j < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
      else { f = b ^ c ^ d; k = 0xca62c1d6; }
      const t = (_rotl(a, 5) + f + e + k + w[j]) >>> 0;
      e = d; d = c; c = _rotl(b, 30); b = a; a = t;
    }

    h0 = (h0 + a) >>> 0;
    h1 = (h1 + b) >>> 0;
    h2 = (h2 + c) >>> 0;
    h3 = (h3 + d) >>> 0;
    h4 = (h4 + e) >>> 0;
  }

  const out: number[] = [];
  for (const h of [h0, h1, h2, h3, h4]) {
    out.push((h >>> 24) & 0xff, (h >>> 16) & 0xff, (h >>> 8) & 0xff, h & 0xff);
  }
  return out;
}

/** HMAC-SHA1，返回 20 字节摘要 */
function _hmacSha1(keyBytes: number[], msgBytes: number[]): number[] {
  const blockSize = 64;
  let key = keyBytes.slice();
  if (key.length > blockSize) key = _sha1(key);
  while (key.length < blockSize) key.push(0);

  const ipad: number[] = key.map(b => b ^ 0x36);
  const opad: number[] = key.map(b => b ^ 0x5c);

  const innerHash = _sha1(ipad.concat(msgBytes));
  return _sha1(opad.concat(innerHash));
}

/** Base64 编码 */
function _base64(bytes: number[]): string {
  const table = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let out = '';
  let i = 0;
  while (i < bytes.length) {
    const b1 = bytes[i++];
    const b2 = i < bytes.length ? bytes[i++] : -1;
    const b3 = i < bytes.length ? bytes[i++] : -1;

    out += table[b1 >> 2];
    out += table[((b1 & 0x03) << 4) | (b2 < 0 ? 0 : (b2 >> 4))];
    out += b2 < 0 ? '=' : table[((b2 & 0x0f) << 2) | (b3 < 0 ? 0 : (b3 >> 6))];
    out += b3 < 0 ? '=' : table[b3 & 0x3f];
  }
  return out;
}

/** HMAC-SHA1，结果 Base64 字符串 */
export function hmacSha1Base64(key: string, message: string): string {
  return _base64(_hmacSha1(_utf8Encode(key), _utf8Encode(message)));
}
