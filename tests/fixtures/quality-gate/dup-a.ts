// VIOLATIONS PLANTED FOR QUALITY-SMOKE (do not fix):
// - jscpd: the renderReport block below is byte-identical across the dup pair
export function renderReport(title: string, rows: number[]): string {
  const header = `=== ${title} ===`;
  const lines: string[] = [header];
  let sum = 0;
  for (const r of rows) {
    sum += r;
    lines.push(`row value ${r}`);
  }
  lines.push(`total ${sum}`);
  return lines.join("\n");
}

export function uniqueToA(): string {
  return "only in dup-a";
}
