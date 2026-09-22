const fs = require('fs');
const vm = require('vm');

const html = fs.readFileSync('Sources/JevBassistCLI/Resources/index.html', 'utf8');
const match = html.match(/<script>([\s\S]*?)<\/script>/);
if (!match) throw new Error('browser script missing');

let now = 0;
let frames = [];
let strokes = 0;
let fills = 0;
const strokeStyles = new Set();
const gradient = {addColorStop() {}};
const context = new Proxy({
  setTransform() {}, fillRect() { fills += 1; }, beginPath() {}, moveTo() {},
  lineTo() {}, bezierCurveTo() {}, quadraticCurveTo() {}, stroke() { strokes += 1; },
  arc() {}, ellipse() {}, fill() { fills += 1; }, save() {}, restore() {},
  createLinearGradient() { return gradient; }, createRadialGradient() { return gradient; }
}, {set(target, property, value) {
  target[property] = value;
  if (property === 'strokeStyle') strokeStyles.add(String(value));
  return true;
}});

function element(id = '') {
  const children = [];
  return {
    id, value: '', textContent: '', disabled: false, hidden: false, children,
    className: '', dataset: {}, style: {setProperty() {}},
    classList: {add() {}, remove() {}, toggle() {}},
    addEventListener() {}, getContext() { return context; },
    replaceChildren(...items) { children.splice(0, children.length, ...items); }
  };
}

const elements = new Map();
const document = {
  body: element('body'), documentElement: element('html'), activeElement: null, hidden: false,
  getElementById(id) {
    if (!elements.has(id)) elements.set(id, element(id));
    return elements.get(id);
  },
  createElement() { return element(); },
  addEventListener() {}
};
const window = {
  devicePixelRatio: 1, innerWidth: 1280, innerHeight: 720,
  addEventListener() {}, matchMedia() { return {matches: false, addEventListener() {}}; }
};
const sandbox = {
  console, document, window, location: {search: '?visual-demo=1'}, URLSearchParams,
  performance: {now: () => now}, requestAnimationFrame(callback) { frames.push(callback); },
  navigator: {mediaDevices: {enumerateDevices: async () => [], addEventListener() {}}},
  fetch: async () => ({ok: true}), EventSource: function () {}, setTimeout, clearTimeout,
  Math, Map, Set, Float32Array, Array, Object, Number, String, Date, Promise
};
vm.runInNewContext(match[1], sandbox, {filename: 'index.html'});

for (let index = 0; index < 460; index++) {
  now += 16;
  const callbacks = frames;
  frames = [];
  for (const callback of callbacks) callback(now);
}

if (strokes < 500) throw new Error(`shared plate did not draw enough structure: ${strokes}`);
if (fills < 100) throw new Error(`shared plate did not maintain its field: ${fills}`);
if (![...strokeStyles].some(value => value.includes('92,225,255'))) {
  throw new Error('companion signal color was not rendered');
}
if (![...strokeStyles].some(value => value.includes('255,54,94'))) {
  throw new Error('downbeat signal color was not rendered');
}
if (elements.get('startOverlay').disabled !== true) {
  throw new Error('visual demo must not expose the live Start control');
}
console.log(`visual demo smoke passed: ${strokes} strokes, ${fills} fills`);
