import { existsSync } from 'fs';
import { resolve } from 'path';

export function getSensitiveRoot(): string {
  const fromEnv = (process.env.SENSITIVE_ROOT || '').trim();
  const root = fromEnv || resolve(process.cwd(), 'Sensitive');
  if (!existsSync(root)) {
    throw new Error(`Sensitive root not found: ${root}. Set SENSITIVE_ROOT or create ./Sensitive`);
  }
  return root;
}

export function resolveSensitivePath(...segments: string[]): string {
  return resolve(getSensitiveRoot(), ...segments);
}
