// Reproduce the source-scanning algorithm without modifying production files.
const assert = require('node:assert/strict');
function missingTooltips(source) {
  const missing = [];
  let start = source.indexOf('IconButton(');
  while (start >= 0) {
    const next = source.indexOf('IconButton(', start + 1);
    const end = next < 0 ? source.length : next;
    if (!/\btooltip\s*:/.test(source.substring(start, end))) missing.push(start);
    start = next;
  }
  return missing;
}
const unlabeled = 'IconButton(icon: const Icon(Icons.add), onPressed: () {})';
const labeledOther = "IconButton.filled(tooltip: 'Другая кнопка', icon: const Icon(Icons.add), onPressed: () {})";
assert.equal(missingTooltips(unlabeled).length, 1);
assert.equal(missingTooltips(`Column(children: [${unlabeled}, ${labeledOther}])`).length, 0);
assert.equal(missingTooltips('IconButton.filled(icon: const Icon(Icons.add), onPressed: () {})').length, 0);
console.log('Confirmed: an unrelated named constructor tooltip hides the missing tooltip; named constructors are not scanned.');
