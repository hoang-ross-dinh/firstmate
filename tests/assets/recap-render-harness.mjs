// Render a built Fleet Recap board's shipped inline script under a minimal DOM
// shim, optionally drive it with scripted captain actions, and print what the
// page actually produced and queued, so board behavior is asserted through the
// real template rather than by reading its source.
//
// Usage: node recap-render-harness.mjs <built-board.html> [actions.json]
// actions.json is an array of:
//   { "click":  { "attr": "data-task", "value": "t1" } }   click by attribute
//   { "click":  { "text": "Show note diff" } }             click by exact text
//   { "check":  { "value": "merge" } }                     check a radio
//   { "fill":   { "name": "comment", "value": "hello" } }  set a field value
//   { "submit": { "question": "t1" } }                     submit a question form
// Prints one JSON document: { nodes, queued, error }.
//   nodes   flat list of {tag, cls, text, attrs, hidden, disabled} in document order
//   queued  every window.lavish.queuePrompt call: {summary, tag, text, data, question}
import { readFileSync } from "node:fs";

const html = readFileSync(process.argv[2], "utf8");
const actions = process.argv[3] ? JSON.parse(readFileSync(process.argv[3], "utf8")) : [];

class Node {
  constructor(tag) {
    this.tagName = tag;
    this.className = "";
    this.children = [];
    this.attributes = {};
    this.listeners = {};
    this._text = "";
    this.hidden = false;
    this.disabled = false;
    this.type = "";
    this.name = "";
    this.value = "";
    this.checked = false;
    this.parentNode = null;
  }
  get textContent() {
    return this.children.length ? this.children.map((c) => c.textContent).join("") : this._text;
  }
  set textContent(v) { this._text = String(v); this.children = []; }
  appendChild(n) { n.parentNode = this; this.children.push(n); return n; }
  setAttribute(k, v) { this.attributes[k] = String(v); }
  addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); }
  fire(type) {
    for (const fn of this.listeners[type] || []) fn({ preventDefault() {} });
  }
}

const all = (root, out = []) => {
  out.push(root);
  root.children.forEach((c) => all(c, out));
  return out;
};

const byId = new Map();
const dataNode = new Node("script");
dataNode.textContent = html
  .split('<script id="bearings-data" type="application/json">')[1]
  .split("</script>")[0];
byId.set("bearings-data", dataNode);
for (const id of ["rb-nav", "rb-app"]) byId.set(id, new Node("div"));

const queued = [];
globalThis.document = {
  createElement: (tag) => new Node(tag),
  getElementById: (id) => byId.get(id) ?? new Node("div"),
};
globalThis.window = {
  lavish: {
    queuePrompt: (summary, opts) =>
      queued.push({
        summary,
        tag: opts.tag,
        text: opts.text,
        data: opts.data,
        question: opts.element?.attributes["data-lavish-question"] ?? null,
      }),
  },
};
globalThis.TextEncoder = TextEncoder;

const script = html.slice(html.indexOf("<script>") + "<script>".length, html.lastIndexOf("</script>"));
let error = "";
try {
  new Function(script)();
  const roots = () => [byId.get("rb-nav"), byId.get("rb-app")].flatMap((r) => all(r));
  for (const a of actions) {
    const [kind, arg] = Object.entries(a)[0];
    const nodes = roots();
    if (kind === "click") {
      const n = nodes.find((x) =>
        arg.attr ? x.attributes[arg.attr] === arg.value : x.textContent === arg.text && !x.children.length);
      if (!n) throw new Error("no node to click: " + JSON.stringify(arg));
      n.fire("click");
    } else if (kind === "check") {
      const n = nodes.find((x) => x.tagName === "input" && x.type === "radio" && x.value === arg.value);
      if (!n) throw new Error("no radio: " + JSON.stringify(arg));
      n.checked = true;
    } else if (kind === "fill") {
      const n = nodes.find((x) => x.name === arg.name);
      if (!n) throw new Error("no field: " + JSON.stringify(arg));
      n.value = arg.value;
    } else if (kind === "submit") {
      const n = nodes.find((x) => x.tagName === "form" && x.attributes["data-lavish-question"] === arg.question);
      if (!n) throw new Error("no form: " + JSON.stringify(arg));
      n.fire("submit");
    }
  }
} catch (e) {
  error = String(e && e.message ? e.message : e);
}

const nodes = [byId.get("rb-nav"), byId.get("rb-app")].flatMap((r) => all(r)).map((n) => ({
  tag: n.tagName,
  cls: n.className,
  text: n.textContent,
  attrs: n.attributes,
  hidden: n.hidden,
  disabled: n.disabled,
}));
process.stdout.write(JSON.stringify({ nodes, queued, error }) + "\n");
