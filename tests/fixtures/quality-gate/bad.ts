// VIOLATIONS PLANTED FOR QUALITY-SMOKE (do not fix):
// - @typescript-eslint/no-unused-vars: unusedValue is declared but never read
// - sonarjs/no-duplicated-branches: pick()'s if/else branches have identical bodies
// - sonarjs/cognitive-complexity: processScores() far exceeds the default threshold (15)
const unusedValue = 42;

export function pick(flag: boolean): number {
  if (flag) {
    return 1;
  } else {
    return 1;
  }
}

export function processScores(scores: number[]): number {
  let total = 0;
  for (const score of scores) {
    if (score > 0) {
      if (score > 10) {
        if (score > 100) {
          total += score;
        } else if (score > 50) {
          total += score * 2;
        } else {
          total += score * 3;
        }
      } else {
        for (let i = 0; i < score; i++) {
          if (i % 2 === 0) {
            total += i;
          } else {
            total -= i;
          }
        }
      }
    } else if (score === 0) {
      total += 1;
    } else {
      let n = score;
      while (n < 0) {
        n += 1;
        if (n === -5) {
          break;
        }
      }
    }
  }
  return total;
}
