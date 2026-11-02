// Minimal WASI preview1 shim for the OMPWeb reactor. The module needs no files, no sockets and no real
// stdin; it needs a clock, randomness and a place to send stdout/stderr. Every other import answers ENOSYS
// (52) so a missing feature fails loudly inside the core instead of silently misbehaving.
const ESUCCESS = 0, EBADF = 8, ENOSYS = 52, ESPIPE = 70;

export class WasiExit extends Error {
  constructor(readonly code: number) { super(`wasi proc_exit(${code})`); }
}

export function makeWasiImports(
  getMemory: () => WebAssembly.Memory,
  names: string[],
  log: (fd: number, text: string) => void,
): Record<string, (...args: any[]) => number> {
  const view = () => new DataView(getMemory().buffer);
  const u8 = () => new Uint8Array(getMemory().buffer);
  const decoder = new TextDecoder();
  const impl: Record<string, (...args: any[]) => number> = {
    args_sizes_get: (argc: number, size: number) => { view().setUint32(argc, 0, true); view().setUint32(size, 0, true); return ESUCCESS; },
    args_get: () => ESUCCESS,
    environ_sizes_get: (count: number, size: number) => { view().setUint32(count, 0, true); view().setUint32(size, 0, true); return ESUCCESS; },
    environ_get: () => ESUCCESS,
    clock_res_get: (_id: number, out: number) => { view().setBigUint64(out, 1000n, true); return ESUCCESS; },
    clock_time_get: (id: number, _precision: bigint, out: number) => {
      const ns = id === 0 ? BigInt(Date.now()) * 1_000_000n : BigInt(Math.round(performance.now() * 1e6));
      view().setBigUint64(out, ns, true);
      return ESUCCESS;
    },
    random_get: (ptr: number, len: number) => {
      const bytes = u8();
      for (let off = 0; off < len; off += 65536) crypto.getRandomValues(bytes.subarray(ptr + off, ptr + Math.min(len, off + 65536)));
      return ESUCCESS;
    },
    fd_write: (fd: number, iovs: number, count: number, written: number) => {
      if (fd !== 1 && fd !== 2) return EBADF;
      const v = view(); let total = 0; let text = "";
      for (let i = 0; i < count; i++) {
        const base = v.getUint32(iovs + i * 8, true), len = v.getUint32(iovs + i * 8 + 4, true);
        text += decoder.decode(u8().subarray(base, base + len), { stream: true });
        total += len;
      }
      v.setUint32(written, total, true);
      if (text) log(fd, text);
      return ESUCCESS;
    },
    fd_read: (_fd: number, _iovs: number, _count: number, nread: number) => { view().setUint32(nread, 0, true); return ESUCCESS; },
    fd_fdstat_get: (fd: number, out: number) => {
      if (fd > 2) return EBADF;
      const v = view();
      v.setUint8(out, 2); v.setUint16(out + 2, 0, true);       // character device, no flags
      v.setBigUint64(out + 8, 0x1fffffffn, true); v.setBigUint64(out + 16, 0n, true);
      return ESUCCESS;
    },
    fd_fdstat_set_flags: () => ESUCCESS,
    fd_close: () => ESUCCESS,
    fd_seek: () => ESPIPE,
    fd_prestat_get: () => EBADF,       // no preopened directories
    fd_prestat_dir_name: () => EBADF,
    sched_yield: () => ESUCCESS,
    proc_exit: (code: number) => { throw new WasiExit(code); },
  };
  const out: Record<string, (...args: any[]) => number> = {};
  for (const name of names) out[name] = impl[name] ?? (() => ENOSYS);
  return out;
}
