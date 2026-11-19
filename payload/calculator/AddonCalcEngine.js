.pragma library

// Advanced calculator engine (serpantinum-addons-v2).
// The expression is plain text (the source of truth, with a cursor); it is tokenized with source ranges,
// parsed leniently (incomplete input still yields a tree with placeholders) and then either evaluated with
// exact rationals or laid out as typeset math (stacked fractions, radicals, superscripts) with caret stops.

var MINUS = "−";
var INV = "⁻¹";   // ⁻¹

function fail(code) {
    throw new Error(code);
}

// ---------------------------------------------------------------- vocabulary

var WORDS = {
    "sin": { fn: "sin" }, "cos": { fn: "cos" }, "tan": { fn: "tan" },
    "sinh": { fn: "sinh" }, "cosh": { fn: "cosh" }, "tanh": { fn: "tanh" },
    "asin": { fn: "sin", inv: true }, "acos": { fn: "cos", inv: true }, "atan": { fn: "tan", inv: true },
    "arcsin": { fn: "sin", inv: true }, "arccos": { fn: "cos", inv: true }, "arctan": { fn: "tan", inv: true },
    "asinh": { fn: "sinh", inv: true }, "acosh": { fn: "cosh", inv: true }, "atanh": { fn: "tanh", inv: true },
    "arsinh": { fn: "sinh", inv: true }, "arcosh": { fn: "cosh", inv: true }, "artanh": { fn: "tanh", inv: true },
    "ln": { fn: "ln" }, "log": { fn: "log" }, "lg": { fn: "log" },
    "sqrt": { fn: "sqrt" }, "cbrt": { fn: "cbrt" }, "root": { fn: "root" },
    "abs": { fn: "abs" }, "exp": { fn: "exp" },
    "floor": { fn: "floor" }, "ceil": { fn: "ceil" }, "round": { fn: "round" },
    "gcd": { fn: "gcd" }, "pgcd": { fn: "gcd" }, "lcm": { fn: "lcm" }, "ppcm": { fn: "lcm" },
    "ncr": { fn: "nCr" }, "npr": { fn: "nPr" },
    "mod": { op: "mod" }, "pi": { c: "π" }, "e": { c: "e" }, "ans": { ans: true }
};

// LaTeX commands typed with a backslash: \pi, \sqrt, \frac, \cdot ...
var LATEX = {
    "pi": "π", "sqrt": "√(", "cbrt": "∛(", "frac": "frac", "cdot": "×", "times": "×",
    "div": "÷", "sin": "sin(", "cos": "cos(", "tan": "tan(", "ln": "ln(", "log": "log(", "exp": "exp(",
    "binom": "nCr(", "lfloor": "floor(", "lceil": "ceil(", "mod": "mod", "bmod": "mod"
};

// min and max argument counts
var FN = {
    "sin": [1, 1], "cos": [1, 1], "tan": [1, 1], "sinh": [1, 1], "cosh": [1, 1], "tanh": [1, 1],
    "ln": [1, 1], "log": [1, 2], "sqrt": [1, 1], "cbrt": [1, 1], "root": [2, 2], "abs": [1, 1], "exp": [1, 1],
    "floor": [1, 1], "ceil": [1, 1], "round": [1, 1], "gcd": [2, 8], "lcm": [2, 8], "nCr": [2, 2], "nPr": [2, 2]
};
var INVERTIBLE = { "sin": 1, "cos": 1, "tan": 1, "sinh": 1, "cosh": 1, "tanh": 1 };
var MAX_WORD = 7;

function lookupWord(word) {
    var w = word.toLowerCase();
    return WORDS.hasOwnProperty(w) ? WORDS[w] : null;
}

function isLetter(c) {
    return c !== "" && /[A-Za-z]/.test(c);
}

function isDigit(c) {
    return c >= "0" && c <= "9";
}

// ---------------------------------------------------------------- tokenizer

// Tokens: num, const, ans, fn, op (+ - * / ÷ ^ mod), lp, rp, sep, fact, pct, err. Every token has [s, e).
function tokenize(text) {
    var s = String(text);
    var toks = [];
    var i = 0;
    while (i < s.length) {
        var c = s.charAt(i);
        if (/\s/.test(c)) { i++; continue; }
        var rest = s.slice(i);
        var m = /^(\d+\.?\d*|\.\d+)(E([+\-−]?)(\d*))?/.exec(rest);
        if (m) {
            toks.push({ t: "num", s: i, e: i + m[0].length, text: m[0], mant: m[1], hasE: m[2] !== undefined, edig: m[4] || "" });
            i += m[0].length;
            continue;
        }
        if (c === "\\") {
            var bm = /^\\[A-Za-z]*/.exec(rest);
            toks.push({ t: "err", s: i, e: i + bm[0].length });
            i += bm[0].length;
            continue;
        }
        if (isLetter(c)) {
            var run = /^[A-Za-z]+/.exec(rest)[0];
            var j = 0;
            while (j < run.length) {
                var hit = null;
                for (var L = Math.min(MAX_WORD, run.length - j); L >= 1; L--) {
                    var info = lookupWord(run.substr(j, L));
                    if (info) { hit = { info: info, len: L }; break; }
                }
                var at = i + j;
                if (!hit) {
                    var last = toks[toks.length - 1];
                    if (last && last.t === "err" && last.e === at) last.e++;
                    else toks.push({ t: "err", s: at, e: at + 1 });
                    j++;
                    continue;
                }
                var tk = { s: at, e: at + hit.len };
                if (hit.info.fn) { tk.t = "fn"; tk.v = hit.info.fn; tk.inv = !!hit.info.inv; }
                else if (hit.info.op) { tk.t = "op"; tk.v = hit.info.op; }
                else if (hit.info.c) { tk.t = "const"; tk.v = hit.info.c; }
                else { tk.t = "ans"; }
                toks.push(tk);
                j += hit.len;
            }
            i += run.length;
            var prev = toks[toks.length - 1];
            if (s.substr(i, 2) === INV && prev && prev.t === "fn" && prev.e === i && INVERTIBLE[prev.v] && !prev.inv) {
                prev.inv = true;
                prev.e += 2;
                i += 2;
            }
            continue;
        }
        var t = null;
        if (c === "+") t = { t: "op", v: "+" };
        else if (c === "-" || c === MINUS || c === "–") t = { t: "op", v: "-" };
        else if (c === "*" || c === "×" || c === "·") t = { t: "op", v: "*" };
        else if (c === "/") t = { t: "op", v: "/" };
        else if (c === "÷" || c === ":") t = { t: "op", v: "÷" };
        else if (c === "^") t = { t: "op", v: "^" };
        else if (c === "(") t = { t: "lp" };
        else if (c === ")") t = { t: "rp" };
        else if (c === ";") t = { t: "sep" };
        else if (c === "!") t = { t: "fact" };
        else if (c === "%") t = { t: "pct" };
        else if (c === "π") t = { t: "const", v: "π" };
        else if (c === "√") t = { t: "fn", v: "sqrt" };
        else if (c === "∛") t = { t: "fn", v: "cbrt" };
        if (t) {
            t.s = i;
            t.e = i + 1;
            toks.push(t);
            i++;
            continue;
        }
        toks.push({ t: "err", s: i, e: i + 1 });
        i++;
    }
    return toks;
}

// ---------------------------------------------------------------- parser

// Lenient recursive descent. Missing operands become {k:"miss"} nodes, unknown input {k:"err"}; the result
// carries bad=true when it cannot be evaluated. Node kinds: num const ans err miss neg pos bin pow post paren fn seq.
function parse(text) {
    var toks = tokenize(text);
    var len = String(text).length;
    var pos = 0;
    var bad = false;

    function peek() { return toks[pos]; }
    function here() { return pos < toks.length ? toks[pos].s : len; }
    function isOp(t, v) { return t !== undefined && t.t === "op" && t.v === v; }
    function startsOperand(t) {
        return t !== undefined && (t.t === "num" || t.t === "const" || t.t === "ans" || t.t === "fn" || t.t === "lp" || t.t === "err");
    }
    function missing() { bad = true; return { k: "miss", at: here() }; }

    function expr() {
        var l = term();
        while (isOp(peek(), "+") || isOp(peek(), "-")) {
            var o = toks[pos++];
            var r = term();
            l = { k: "bin", op: o.v, os: o.s, oe: o.e, l: l, r: r };
        }
        return l;
    }

    function term() {
        var l = unary();
        for (;;) {
            var t = peek();
            if (t !== undefined && t.t === "op" && (t.v === "*" || t.v === "/" || t.v === "÷" || t.v === "mod")) {
                pos++;
                var r = unary();
                l = { k: "bin", op: t.v, os: t.s, oe: t.e, l: l, r: r };
            } else if (startsOperand(t)) {
                var before = toks[pos - 1];
                if (t.t === "num" && before && before.t === "num") bad = true;
                var r2 = unary();
                l = { k: "bin", op: "*", implicit: true, os: t.s, oe: t.s, l: l, r: r2 };
            } else {
                break;
            }
        }
        return l;
    }

    function unary() {
        var t = peek();
        if (isOp(t, "-") || isOp(t, "+")) {
            pos++;
            return { k: t.v === "-" ? "neg" : "pos", s: t.s, e: t.e, arg: unary() };
        }
        return power();
    }

    function power() {
        var b = postfix();
        if (isOp(peek(), "^")) {
            var o = toks[pos++];
            return { k: "pow", os: o.s, oe: o.e, base: b, exp: unary() };
        }
        return b;
    }

    function postfix() {
        var p = primary();
        while (peek() !== undefined && (peek().t === "fact" || peek().t === "pct")) {
            var t = toks[pos++];
            p = { k: "post", op: t.t === "fact" ? "!" : "%", s: t.s, e: t.e, arg: p };
        }
        return p;
    }

    function argument() {
        var t = peek();
        if (t === undefined || t.t === "rp" || t.t === "sep") return missing();
        return expr();
    }

    function bareArgument() {
        var t = peek();
        if (isOp(t, "-") || isOp(t, "+")) {
            pos++;
            return { k: t.v === "-" ? "neg" : "pos", s: t.s, e: t.e, arg: bareArgument() };
        }
        return postfix();
    }

    function primary() {
        var t = peek();
        if (t === undefined || t.t === "op" || t.t === "rp" || t.t === "sep" || t.t === "fact" || t.t === "pct") return missing();
        pos++;
        if (t.t === "num") {
            if (t.hasE && t.edig === "") bad = true;
            return { k: "num", s: t.s, e: t.e, text: String(text).slice(t.s, t.e), tok: t };
        }
        if (t.t === "const") return { k: "const", s: t.s, e: t.e, name: t.v };
        if (t.t === "ans") return { k: "ans", s: t.s, e: t.e };
        if (t.t === "err") { bad = true; return { k: "err", s: t.s, e: t.e }; }
        if (t.t === "lp") {
            var inner = argument();
            var node = { k: "paren", s: t.s, e: -1, inner: inner, closed: false };
            if (peek() !== undefined && peek().t === "rp") {
                node.e = toks[pos].e;
                node.closed = true;
                pos++;
            }
            return node;
        }
        // function
        var fn = { k: "fn", name: t.v, inv: !!t.inv, ns: t.s, ne: t.e, lp: -1, rp: -1, seps: [], args: [], bare: false };
        if (peek() !== undefined && peek().t === "lp") {
            fn.lp = toks[pos].s;
            pos++;
            fn.args.push(argument());
            while (peek() !== undefined && peek().t === "sep") {
                fn.seps.push(toks[pos].s);
                pos++;
                fn.args.push(argument());
            }
            if (peek() !== undefined && peek().t === "rp") {
                fn.rp = toks[pos].s;
                pos++;
            }
        } else {
            fn.bare = true;
            var nx = peek();
            if (nx === undefined || !(startsOperand(nx) || isOp(nx, "-") || isOp(nx, "+"))) fn.args.push(missing());
            else fn.args.push(bareArgument());
        }
        var arity = FN[fn.name];
        if (!arity || fn.args.length < arity[0] || fn.args.length > arity[1]) bad = true;
        return fn;
    }

    if (toks.length === 0) return { root: { k: "miss", at: 0 }, bad: true, empty: true, toks: toks };
    var items = [expr()];
    while (pos < toks.length) {
        var stray = toks[pos++];
        bad = true;
        items.push({ k: "err", s: stray.s, e: stray.e });
        if (pos < toks.length) {
            var nt = toks[pos];
            if (nt.t !== "rp" && nt.t !== "sep") items.push(expr());
        }
    }
    var root = items.length === 1 ? items[0] : { k: "seq", items: items };
    return { root: root, bad: bad, empty: false, toks: toks };
}

function nodeEnd(n) {
    switch (n.k) {
    case "num": case "const": case "ans": case "err": case "post": return n.e;
    case "miss": return n.at;
    case "neg": case "pos": return nodeEnd(n.arg);
    case "bin": return nodeEnd(n.r);
    case "pow": return nodeEnd(n.exp);
    case "paren": return n.closed ? n.e : nodeEnd(n.inner);
    case "fn":
        if (n.rp >= 0) return n.rp + 1;
        return n.args.length ? Math.max(n.ne, nodeEnd(n.args[n.args.length - 1])) : n.ne;
    case "seq": return nodeEnd(n.items[n.items.length - 1]);
    }
    return 0;
}

function nodeStart(n) {
    switch (n.k) {
    case "num": case "const": case "ans": case "err": case "neg": case "pos": case "paren": return n.s;
    case "miss": return n.at;
    case "bin": return nodeStart(n.l);
    case "pow": return nodeStart(n.base);
    case "post": return nodeStart(n.arg);
    case "fn": return n.ns;
    case "seq": return nodeStart(n.items[0]);
    }
    return 0;
}

// ---------------------------------------------------------------- exact values

function gcd(a, b) {
    a = Math.abs(a);
    b = Math.abs(b);
    while (b) {
        var t = a % b;
        a = b;
        b = t;
    }
    return a;
}

function safe(x) {
    return Number.isSafeInteger(x);
}

function F(x) {
    if (!isFinite(x)) fail(isNaN(x) ? "domain" : "overflow");
    return { q: false, v: x };
}

function Q(n, d) {
    if (d === undefined) d = 1;
    if (d === 0) fail("div0");
    if (!safe(n) || !safe(d)) return F(n / d);
    if (d < 0) { n = -n; d = -d; }
    var g = gcd(n, d) || 1;
    return { q: true, n: n / g, d: d / g };
}

function num(v) {
    return v.q ? v.n / v.d : v.v;
}

function isInt(v) {
    return v.q ? v.d === 1 : Number.isInteger(v.v);
}

function add(a, b) {
    if (a.q && b.q) {
        var n1 = a.n * b.d, n2 = b.n * a.d, d = a.d * b.d;
        if (safe(n1) && safe(n2) && safe(d) && safe(n1 + n2)) return Q(n1 + n2, d);
    }
    return F(num(a) + num(b));
}

function neg(a) {
    return a.q ? Q(-a.n, a.d) : F(-a.v);
}

function mul(a, b) {
    if (a.q && b.q) {
        var g1 = gcd(a.n, b.d) || 1, g2 = gcd(b.n, a.d) || 1;
        var n = (a.n / g1) * (b.n / g2), d = (a.d / g2) * (b.d / g1);
        if (safe(n) && safe(d)) return Q(n, d);
    }
    return F(num(a) * num(b));
}

function isZero(v) {
    return v.q ? v.n === 0 : v.v === 0;
}

function div(a, b) {
    if (isZero(b)) fail("div0");
    if (b.q) return mul(a, Q(b.d, b.n));
    return F(num(a) / num(b));
}

function intRoot(n, k) {
    // exact integer k-th root of n >= 0, or -1
    var r = Math.round(Math.pow(n, 1 / k));
    for (var c = Math.max(0, r - 1); c <= r + 1; c++) {
        var p = 1;
        for (var i = 0; i < k; i++) p *= c;
        if (p === n) return c;
    }
    return -1;
}

function exactRoot(v, k) {
    // exact k-th root of a rational, or null
    if (!v.q) return null;
    var negative = v.n < 0;
    if (negative && k % 2 === 0) return null;
    var rn = intRoot(Math.abs(v.n), k), rd = intRoot(v.d, k);
    if (rn < 0 || rd < 0) return null;
    return Q(negative ? -rn : rn, rd);
}

function powInt(a, e) {
    // a rational, e integer
    if (e < 0) {
        if (isZero(a)) fail("div0");
        return div(Q(1), powInt(a, -e));
    }
    var result = Q(1), base = a;
    while (e > 0) {
        if (e & 1) result = mul(result, base);
        e = Math.floor(e / 2);
        if (e > 0) base = mul(base, base);
        if (!result.q || !base.q) return null;
    }
    return result;
}

function power(a, b) {
    if (isZero(a) && num(b) < 0) fail("div0");
    if (a.q && b.q && b.d === 1 && Math.abs(b.n) <= 4096) {
        var exact = powInt(a, b.n);
        if (exact) return exact;
    }
    if (a.q && b.q && b.d > 1 && b.d <= 64) {
        var root = exactRoot(a, b.d);
        if (root && Math.abs(b.n) <= 4096) {
            var r = powInt(root, b.n);
            if (r) return r;
        }
        if (a.n < 0 && b.d % 2 === 1) {
            var mag = Math.pow(-num(a), b.n / b.d);
            return F(b.n % 2 === 0 ? mag : -mag);
        }
    }
    var x = Math.pow(num(a), num(b));
    if (isNaN(x)) fail("domain");
    return F(x);
}

function factorial(v) {
    if (!isInt(v) || num(v) < 0) fail("domain");
    var n = num(v);
    if (n > 170) fail("overflow");
    var r = Q(1);
    for (var k = 2; k <= n; k++) r = mul(r, Q(k));
    return r;
}

function snap(x) {
    return Math.abs(x) < 1e-15 ? 0 : x;
}

function angleFactor(mode) {
    if (mode === "deg") return Math.PI / 180;
    if (mode === "grad") return Math.PI / 200;
    return 1;
}

function requireInt(v) {
    if (!isInt(v)) fail("domain");
    return num(v);
}

function applyFn(node, args, angle) {
    var name = node.name, x = args[0], xv = num(x), k = angleFactor(angle);
    if (node.inv) {
        switch (name) {
        case "sin": if (xv < -1 || xv > 1) fail("domain"); return F(Math.asin(xv) / k);
        case "cos": if (xv < -1 || xv > 1) fail("domain"); return F(Math.acos(xv) / k);
        case "tan": return F(Math.atan(xv) / k);
        case "sinh": return F(Math.asinh(xv));
        case "cosh": if (xv < 1) fail("domain"); return F(Math.acosh(xv));
        case "tanh": if (xv <= -1 || xv >= 1) fail("domain"); return F(Math.atanh(xv));
        }
    }
    switch (name) {
    case "sin": return F(snap(Math.sin(xv * k)));
    case "cos": return F(snap(Math.cos(xv * k)));
    case "tan":
        var c = snap(Math.cos(xv * k));
        if (c === 0) fail("domain");
        return F(snap(Math.sin(xv * k)) / c);
    case "sinh": return F(Math.sinh(xv));
    case "cosh": return F(Math.cosh(xv));
    case "tanh": return F(Math.tanh(xv));
    case "ln":
        if (xv <= 0) fail("domain");
        return F(Math.log(xv));
    case "log":
        if (args.length === 2) {
            var base = xv, y = num(args[1]);
            if (base <= 0 || base === 1 || y <= 0) fail("domain");
            var exactLog = Math.round(Math.log(y) / Math.log(base));
            if (args[0].q && args[1].q && Math.abs(exactLog) < 64) {
                var p = powInt(args[0], exactLog);
                if (p && p.q && p.n === args[1].n && p.d === args[1].d) return Q(exactLog);
            }
            return F(Math.log(y) / Math.log(base));
        }
        if (xv <= 0) fail("domain");
        return F(snap(Math.log10(xv)));
    case "sqrt":
        if (xv < 0) fail("domain");
        return exactRoot(x, 2) || F(Math.sqrt(xv));
    case "cbrt":
        return exactRoot(x, 3) || F(Math.cbrt(xv));
    case "root":
        var n = requireInt(args[0]), radicand = args[1], rv = num(radicand);
        if (n < 1) fail("domain");
        if (rv < 0 && n % 2 === 0) fail("domain");
        var er = exactRoot(radicand, n);
        if (er) return er;
        return F(rv < 0 ? -Math.pow(-rv, 1 / n) : Math.pow(rv, 1 / n));
    case "abs": return x.q ? Q(Math.abs(x.n), x.d) : F(Math.abs(xv));
    case "exp": return F(Math.exp(xv));
    case "floor": return x.q ? Q(Math.floor(x.n / x.d)) : F(Math.floor(xv));
    case "ceil": return x.q ? Q(Math.ceil(x.n / x.d)) : F(Math.ceil(xv));
    case "round":
        var r = Math.sign(xv) * Math.floor(Math.abs(xv) + 0.5);
        return x.q ? Q(r) : F(r);
    case "gcd": case "lcm":
        var acc = Math.abs(requireInt(args[0]));
        for (var i = 1; i < args.length; i++) {
            var b = Math.abs(requireInt(args[i]));
            if (name === "gcd") acc = gcd(acc, b);
            else acc = (acc === 0 || b === 0) ? 0 : acc / gcd(acc, b) * b;
        }
        return Number.isSafeInteger(acc) ? Q(acc) : F(acc);
    case "nCr": case "nPr":
        var nn = requireInt(args[0]), kk = requireInt(args[1]);
        if (nn < 0 || kk < 0 || kk > nn) fail("domain");
        if (name === "nCr" && kk > nn - kk) kk = nn - kk;
        var res = Q(1);
        for (var j = 0; j < kk; j++) {
            res = mul(res, Q(nn - j));
            if (name === "nCr") res = div(res, Q(j + 1));
        }
        return res;
    }
    fail("syntax");
}

function numberValue(node) {
    var t = node.tok;
    var mant = t.mant;
    var dot = mant.indexOf(".");
    var digits = mant.replace(".", "");
    var scale = dot < 0 ? 0 : mant.length - dot - 1;
    var v = digits.length <= 15 ? Q(parseInt(digits || "0", 10), Math.pow(10, scale)) : F(parseFloat(mant));
    if (t.hasE) {
        var ex = parseInt(t.edig, 10);
        var signChar = node.text.charAt(node.text.indexOf("E") + 1);
        if (signChar === "-" || signChar === MINUS) ex = -ex;
        if (Math.abs(ex) > 400) return F(parseFloat(mant) * Math.pow(10, ex));
        var p = powInt(Q(10), ex);
        v = p ? mul(v, p) : F(num(v) * Math.pow(10, ex));
    }
    return v;
}

function evalNode(n, ctx) {
    switch (n.k) {
    case "num": return numberValue(n);
    case "const": return F(n.name === "e" ? Math.E : Math.PI);
    case "ans": return ctx.ans || Q(0);
    case "miss": case "err": case "seq": fail("syntax");
    case "neg": return neg(evalNode(n.arg, ctx));
    case "pos": return evalNode(n.arg, ctx);
    case "paren": return evalNode(n.inner, ctx);
    case "post":
        if (n.op === "!") return factorial(evalNode(n.arg, ctx));
        return div(evalNode(n.arg, ctx), Q(100));
    case "pow": return power(evalNode(n.base, ctx), evalNode(n.exp, ctx));
    case "fn":
        var args = [];
        for (var i = 0; i < n.args.length; i++) args.push(evalNode(n.args[i], ctx));
        return applyFn(n, args, ctx.angle);
    case "bin":
        var l = evalNode(n.l, ctx);
        if ((n.op === "+" || n.op === "-") && n.r.k === "post" && n.r.op === "%") {
            // 200 + 10% = 220: a percentage added to or taken from a value is relative to it
            var part = mul(l, div(evalNode(n.r.arg, ctx), Q(100)));
            return n.op === "+" ? add(l, part) : add(l, neg(part));
        }
        var r = evalNode(n.r, ctx);
        switch (n.op) {
        case "+": return add(l, r);
        case "-": return add(l, neg(r));
        case "*": return mul(l, r);
        case "/": case "÷": return div(l, r);
        case "mod":
            if (isZero(r)) fail("div0");
            var q = div(l, r);
            var fl = q.q ? Q(Math.floor(q.n / q.d)) : F(Math.floor(num(q)));
            return add(l, neg(mul(r, fl)));
        }
    }
    fail("syntax");
}

// ---------------------------------------------------------------- formatting

function trimMantissa(m) {
    return m.indexOf(".") < 0 ? m : m.replace(/0+$/, "").replace(/\.$/, "");
}

function formatNumber(x) {
    if (!isFinite(x)) fail("overflow");
    if (x === 0) return "0";
    var neg = x < 0, a = Math.abs(x), s;
    if (Number.isInteger(a) && a < 1e15) {
        s = String(a);
    } else if (a >= 1e15 || a < 1e-9) {
        var parts = a.toExponential(11).split("e");
        var ex = parseInt(parts[1], 10);
        s = trimMantissa(parts[0]) + "E" + (ex < 0 ? MINUS : "") + Math.abs(ex);
    } else {
        s = String(Number(a.toPrecision(12)));
        if (s.indexOf("e") >= 0) {
            var p = s.split("e");
            var e2 = parseInt(p[1], 10);
            s = trimMantissa(p[0]) + "E" + (e2 < 0 ? MINUS : "") + Math.abs(e2);
        }
    }
    return (neg ? MINUS : "") + s;
}

function approxFraction(x, maxDen) {
    var a = Math.abs(x), b = a;
    var h0 = 0, h1 = 1, k0 = 1, k1 = 0;
    for (var i = 0; i < 64; i++) {
        var ai = Math.floor(b);
        var h2 = ai * h1 + h0, k2 = ai * k1 + k0;
        if (k2 > maxDen) break;
        h0 = h1; h1 = h2; k0 = k1; k1 = k2;
        var frac = b - ai;
        if (frac < 1e-12) break;
        b = 1 / frac;
    }
    if (k1 === 0) return null;
    var p = x < 0 ? -h1 : h1;
    if (Math.abs(p / k1 - x) > 1e-12 * Math.max(1, Math.abs(x))) return null;
    return { p: p, q: k1 };
}

function signed(text, negative) {
    return (negative ? MINUS : "") + text;
}

function terminates(d) {
    while (d % 2 === 0) d /= 2;
    while (d % 5 === 0) d /= 5;
    return d === 1;
}

// Exact form of a value: "3/4", "2π/3", "√3/2", "2√2". null when the decimal is already exact or nothing fits.
function exactForm(v) {
    if (v.q) {
        if (v.d === 1) return null;
        if (String(Math.abs(v.n)).length + String(v.d).length > 18) return null;
        return { text: signed(Math.abs(v.n) + "/" + v.d, v.n < 0), kind: "frac", den: v.d, terminating: terminates(v.d) };
    }
    var x = v.v;
    if (x === 0 || Math.abs(x) > 1e9 || Math.abs(x) < 1e-6) return null;
    if (Math.abs(x - Math.round(x)) <= 1e-12 * Math.max(1, Math.abs(x))) return null;
    var f = approxFraction(x, 1000);
    if (f && f.q > 1) return { text: signed(Math.abs(f.p) + "/" + f.q, f.p < 0), kind: "frac", den: f.q, terminating: terminates(f.q) };
    var pf = approxFraction(x / Math.PI, 100);
    if (pf && pf.p !== 0 && Math.abs(pf.p) <= 1000) {
        var coef = Math.abs(pf.p) === 1 ? "" : String(Math.abs(pf.p));
        return { text: signed(coef + "π" + (pf.q > 1 ? "/" + pf.q : ""), pf.p < 0), kind: "pi", den: pf.q };
    }
    var sq = approxFraction(x * x, 1000);
    if (sq && sq.p > 0 && sq.p <= 1000000) {
        var m = sq.p * sq.q, outside = 1;
        for (var i = 2; i * i <= m; i++) {
            while (m % (i * i) === 0) {
                outside *= i;
                m /= i * i;
            }
        }
        if (m > 1) {
            var den = sq.q, g = gcd(outside, den);
            outside /= g;
            den /= g;
            var body = (outside === 1 ? "" : String(outside)) + "√" + m + (den > 1 ? "/" + den : "");
            return { text: signed(body, x < 0), kind: "sqrt", den: den };
        }
    }
    return null;
}

function preferExact(form, text, advanced) {
    if (!form) return false;
    var typedFraction = String(text).indexOf("/") >= 0;
    if (typedFraction) return form.kind !== "frac" || form.den <= 100000;
    if (!advanced) return false;
    if (form.kind !== "frac") return true;
    return !form.terminating && form.den <= 1000;
}

// Evaluate an expression. opts: {angle, ans (value), advanced}.
// Returns {ok, error, incomplete, value, decimal, exact, primary, alternate}.
function compute(text, opts) {
    opts = opts || {};
    var tree = parse(text);
    if (tree.empty) return { ok: false, error: "empty", incomplete: true };
    if (tree.bad) return { ok: false, error: "syntax", incomplete: hasMissing(tree.root) };
    var v;
    try {
        v = evalNode(tree.root, { angle: opts.angle || "deg", ans: opts.ans || null });
        if (!isFinite(num(v))) fail("overflow");
    } catch (err) {
        var code = err.message === "div0" || err.message === "domain" || err.message === "overflow" ? err.message : "syntax";
        return { ok: false, error: code, incomplete: false };
    }
    var decimal = formatNumber(num(v));
    var form = exactForm(v);
    var exact = form ? form.text : null;
    var useExact = preferExact(form, text, !!opts.advanced);
    return {
        ok: true, value: v, decimal: decimal, exact: exact,
        primary: useExact ? exact : decimal,
        alternate: exact === null ? "" : (useExact ? decimal : exact)
    };
}

function hasMissing(n) {
    if (!n) return false;
    switch (n.k) {
    case "miss": return true;
    case "neg": case "pos": case "post": return hasMissing(n.arg);
    case "bin": return hasMissing(n.l) || hasMissing(n.r);
    case "pow": return hasMissing(n.base) || hasMissing(n.exp);
    case "paren": return hasMissing(n.inner);
    case "fn":
        for (var i = 0; i < n.args.length; i++) if (hasMissing(n.args[i])) return true;
        return false;
    }
    return false;
}

function hasOperation(text) {
    var toks = tokenize(text);
    if (toks.length === 0) return false;
    return !(toks.length === 1 && toks[0].t === "num" && !toks[0].hasE);
}

function valueOf(text, angle) {
    var r = compute(text, { angle: angle || "deg" });
    return r.ok ? r.value : null;
}

function openCount(text) {
    var open = 0;
    for (var i = 0; i < text.length; i++) {
        var c = text.charAt(i);
        if (c === "(") open++;
        else if (c === ")" && open > 0) open--;
    }
    return open;
}

function closeParens(text) {
    var out = text;
    for (var n = openCount(text); n > 0; n--) out += ")";
    return out;
}

// ---------------------------------------------------------------- export (plain text and LaTeX)

function plainNumber(text) {
    return text.replace(/−/g, "-").replace("E", "e");
}

var PLAIN_NAMES = { "sqrt": "sqrt", "cbrt": "cbrt" };

function toPlain(text) {
    var tree = parse(text);
    if (tree.empty) return "";
    return plainNode(tree.root, 0);
}

function plainWrap(n, minPrec) {
    var s = plainNode(n, minPrec);
    return precedence(n) < minPrec ? "(" + s + ")" : s;
}

function precedence(n) {
    switch (n.k) {
    case "bin": return (n.op === "+" || n.op === "-") ? 1 : 2;
    case "neg": case "pos": return 3;
    case "pow": return 4;
    }
    return 5;
}

function plainNode(n, minPrec) {
    switch (n.k) {
    case "num": return plainNumber(n.text);
    case "const": return n.name === "e" ? "e" : "pi";
    case "ans": return "Ans";
    case "miss": return "";
    case "err": return "";
    case "seq": return n.items.map(function (x) { return plainNode(x, 0); }).join(" ");
    case "neg": return "-" + plainWrap(n.arg, 3);
    case "pos": return "+" + plainWrap(n.arg, 3);
    case "paren": return "(" + plainNode(n.inner, 0) + ")";
    case "post": return plainWrap(n.arg, 5) + n.op;
    case "pow": return plainWrap(n.base, 5) + "^" + plainWrap(n.exp, 4);
    case "bin":
        var p = precedence(n);
        var op = n.op === "÷" ? "/" : (n.op === "mod" ? " mod " : n.op);
        var left = plainWrap(n.l, p);
        var right = plainWrap(n.r, p + (n.op === "-" || n.op === "/" || n.op === "÷" ? 1 : 0));
        if (n.op === "+" || n.op === "-") op = " " + op + " ";
        return left + op + right;
    case "fn":
        var name = (n.inv ? "a" : "") + (PLAIN_NAMES[n.name] || n.name);
        return name + "(" + n.args.map(function (x) { return plainNode(x, 0); }).join(", ") + ")";
    }
    return "";
}

var TEX_FN = {
    "sin": "\\sin", "cos": "\\cos", "tan": "\\tan", "sinh": "\\sinh", "cosh": "\\cosh", "tanh": "\\tanh",
    "ln": "\\ln", "log": "\\log", "exp": "\\exp", "gcd": "\\gcd", "lcm": "\\operatorname{lcm}", "round": "\\operatorname{round}"
};

function toLatex(text) {
    var tree = parse(text);
    if (tree.empty) return "";
    return texNode(tree.root);
}

function texGroup(n) {
    return "{" + texNode(n) + "}";
}

function texStrip(n) {
    return n.k === "paren" ? n.inner : n;
}

function texNumber(text) {
    var m = /^([^E]*)E([−\-+]?)(\d*)$/.exec(text);
    if (!m) return text;
    return m[1] + " \\times 10^{" + (m[2] === "+" ? "" : (m[2] ? "-" : "")) + m[3] + "}";
}

function texNode(n) {
    switch (n.k) {
    case "num": return texNumber(n.text);
    case "const": return n.name === "e" ? "e" : "\\pi";
    case "ans": return "\\mathrm{Ans}";
    case "miss": return "\\square";
    case "err": return "";
    case "seq": return n.items.map(texNode).join(" ");
    case "neg": return "-" + texNode(n.arg);
    case "pos": return "+" + texNode(n.arg);
    case "paren": return "\\left(" + texNode(n.inner) + "\\right)";
    case "post": return texNode(n.arg) + (n.op === "%" ? "\\%" : "!");
    case "pow": return (n.base.k === "fn" || n.base.k === "pow" || n.base.k === "bin" || n.base.k === "neg" ? "\\left(" + texNode(n.base) + "\\right)" : texGroup(n.base)) + "^" + texGroup(texStrip(n.exp));
    case "bin":
        if (n.op === "/") {
            if (n.l.k === "neg") return "-\\frac" + texGroup(texStrip(n.l.arg)) + texGroup(texStrip(n.r));
            return "\\frac" + texGroup(texStrip(n.l)) + texGroup(texStrip(n.r));
        }
        if (n.implicit) return texNode(n.l) + (n.r.k === "num" ? " \\cdot " : " ") + texNode(n.r);
        var op = { "+": " + ", "-": " - ", "*": " \\times ", "÷": " \\div ", "mod": " \\bmod " }[n.op];
        return texNode(n.l) + op + texNode(n.r);
    case "fn":
        var a = n.args;
        switch (n.name) {
        case "sqrt": return "\\sqrt" + texGroup(texStrip(a[0]));
        case "cbrt": return "\\sqrt[3]" + texGroup(texStrip(a[0]));
        case "root": return "\\sqrt[" + texNode(a[0]) + "]" + texGroup(a[1] || { k: "miss" });
        case "abs": return "\\left|" + texNode(a[0]) + "\\right|";
        case "floor": return "\\left\\lfloor " + texNode(a[0]) + "\\right\\rfloor";
        case "ceil": return "\\left\\lceil " + texNode(a[0]) + "\\right\\rceil";
        case "nCr": return "\\binom" + texGroup(a[0]) + texGroup(a[1] || { k: "miss" });
        case "nPr": return "P\\left(" + texNode(a[0]) + ", " + texNode(a[1] || { k: "miss" }) + "\\right)";
        case "log":
            if (a.length === 2) return "\\log_" + texGroup(a[0]) + "\\left(" + texNode(a[1]) + "\\right)";
        }
        var name = TEX_FN[n.name] || ("\\operatorname{" + n.name + "}");
        if (n.inv) name += "^{-1}";
        return name + "\\left(" + a.map(texNode).join(", ") + "\\right)";
    }
    return "";
}

// ---------------------------------------------------------------- editing

// State: {t: text, c: cursor, a: selection anchor}. Every operation returns a new state.

function mk(t, c, a) {
    return { t: t, c: c, a: a === undefined ? c : a };
}

function selRange(st) {
    return [Math.min(st.a, st.c), Math.max(st.a, st.c)];
}

function hasSel(st) {
    return st.a !== st.c;
}

function dropSel(st) {
    if (!hasSel(st)) return st;
    var r = selRange(st);
    return mk(st.t.slice(0, r[0]) + st.t.slice(r[1]), r[0]);
}

function insertRaw(st, str, caretOffset) {
    st = dropSel(st);
    var off = caretOffset === undefined ? str.length : caretOffset;
    return mk(st.t.slice(0, st.c) + str + st.t.slice(st.c), st.c + off);
}

function tokenEndingAt(text, i) {
    var toks = tokenize(text);
    for (var k = toks.length - 1; k >= 0; k--) {
        if (toks[k].e === i) return toks[k];
        if (toks[k].e < i) break;
    }
    return null;
}

function tokenStartingAt(text, i) {
    var toks = tokenize(text);
    for (var k = 0; k < toks.length; k++) {
        if (toks[k].s === i) return toks[k];
        if (toks[k].s > i) break;
    }
    return null;
}

function operandEndsAt(text, i) {
    var t = tokenEndingAt(text, i);
    return !!t && (t.t === "num" || t.t === "const" || t.t === "ans" || t.t === "rp" || t.t === "fact" || t.t === "pct");
}

function operandStartsAt(text, i) {
    var t = tokenStartingAt(text, i);
    return !!t && (t.t === "num" || t.t === "const" || t.t === "ans" || t.t === "fn" || t.t === "lp");
}

function isOperatorChar(c) {
    return c !== "" && "+−×÷/^".indexOf(c) >= 0;
}

// Positions the caret may stop at: not inside a word, not between a function and its "(", not inside the
// hidden joints of a template ("/(" "^(" and the ")" that closes a fraction numerator).
function validStops(text) {
    var n = text.length;
    var ok = [];
    for (var i = 0; i <= n; i++) ok.push(true);
    var toks = tokenize(text);
    for (var k = 0; k < toks.length; k++) {
        var t = toks[k];
        if (t.t === "fn" || t.t === "ans" || (t.t === "op" && t.v === "mod") || (t.t === "const" && t.e - t.s > 1)) {
            for (var j = t.s + 1; j < t.e; j++) ok[j] = false;
        }
        var nx = toks[k + 1];
        if (nx && nx.t === "lp" && nx.s === t.e) {
            if (t.t === "fn" || (t.t === "op" && (t.v === "/" || t.v === "^"))) ok[t.e] = false;
        }
        if (t.t === "rp" && nx && nx.s === t.e && nx.t === "op" && nx.v === "/") ok[t.e] = false;
    }
    return ok;
}

function moveCaret(st, dir, extend) {
    var ok = validStops(st.t);
    var c = st.c;
    if (!extend && hasSel(st)) {
        var r = selRange(st);
        return mk(st.t, dir < 0 ? r[0] : r[1]);
    }
    do {
        c += dir;
    } while (c > 0 && c < st.t.length && !ok[c]);
    c = Math.max(0, Math.min(st.t.length, c));
    return extend ? mk(st.t, c, st.a) : mk(st.t, c);
}

function snapCaret(text, c) {
    var ok = validStops(text);
    c = Math.max(0, Math.min(text.length, c));
    while (c > 0 && !ok[c]) c--;
    return c;
}

function isPlainResult(text) {
    return /^[0-9.]+(E−?\d+)?$/.test(text) || text === "π" || text === "e" || text === "Ans";
}

function wrapResult(text) {
    return isPlainResult(text) ? text : "(" + text + ")";
}

// Insert an opening construct ending with "(" (a function, "√(", "(", "^(", "/("): the closing ")" is added
// when nothing follows; when an operand follows, a single-argument function takes it bare (√2, sin 30).
function insertOpening(st, token, singleArg) {
    if (hasSel(st)) {
        var r = selRange(st);
        var inner = st.t.slice(r[0], r[1]);
        var wrapped = token + inner + ")";
        return mk(st.t.slice(0, r[0]) + wrapped + st.t.slice(r[1]), r[0] + wrapped.length);
    }
    if (operandStartsAt(st.t, st.c)) {
        if (singleArg && token !== "(" && token.charAt(token.length - 1) === "(") return insertRaw(st, token.slice(0, -1));
        return insertRaw(st, token);
    }
    return insertRaw(st, token + ")", token.length);
}

function fnSingleArg(token) {
    var tree = tokenize(token.replace(/\($/, ""));
    if (tree.length !== 1 || tree[0].t !== "fn") return false;
    var a = FN[tree[0].v];
    return !!a && a[0] === 1;
}

// Keypad and keyboard actions. ctx: {evaluated, hasAns}. Returns {st, equals?}.
function act(st, action, arg, ctx) {
    ctx = ctx || {};
    var t = st.t;
    if (ctx.evaluated) {
        switch (action) {
        case "digit": case "dot": case "const": case "open": case "insert": case "exp10":
            st = mk("", 0);
            break;
        case "fn":
            var w = arg + t + ")";
            return { st: mk(w, w.length) };
        case "frac":
            var f = wrapResult(t) + "/()";
            return { st: mk(f, f.length - 1) };
        case "pow":
            var p = wrapResult(t) + "^()";
            return { st: mk(p, p.length - 1) };
        case "postfix":
            var q = wrapResult(t) + arg;
            return { st: mk(q, q.length) };
        default:
            st = mk(t, t.length);
        }
        t = st.t;
    }
    switch (action) {
    case "digit": return { st: inputDigit(st, arg) };
    case "dot": return { st: inputDot(st) };
    case "op": return { st: inputOperator(st, arg, ctx) };
    case "const": return { st: insertRaw(st, arg) };
    case "exp10":
        if (!operandEndsAt(dropSel(st).t, dropSel(st).c)) st = insertRaw(st, "1");
        return { st: insertRaw(st, "E") };
    case "open": return { st: insertOpening(st, "(", false) };
    case "close": return { st: inputClose(st) };
    case "smartParen": return { st: smartParen(st) };
    case "fn": return { st: insertOpening(st, arg, fnSingleArg(arg)) };
    case "frac": return { st: inputFraction(st) };
    case "pow": return { st: inputTemplateOp(st, "^") };
    case "postfix": return { st: inputPostfix(st, arg) };
    case "back": return { st: backspace(st) };
    case "del": return { st: deleteForward(st) };
    case "left": return { st: moveCaret(st, -1, !!arg) };
    case "right": return { st: moveCaret(st, 1, !!arg) };
    case "home": return { st: arg ? mk(t, 0, st.a) : mk(t, 0) };
    case "end": return { st: arg ? mk(t, t.length, st.a) : mk(t, t.length) };
    case "selectAll": return { st: mk(t, t.length, 0) };
    case "clear": return { st: mk("", 0) };
    case "insert": return { st: insertText(st, arg) };
    case "char": return typeChar(st, arg, ctx);
    }
    return { st: st };
}

function inputDigit(st, d) {
    st = dropSel(st);
    var m = /(\d*\.?\d*)$/.exec(st.t.slice(0, st.c));
    var seg = m ? m[1] : "";
    var next = st.t.charAt(st.c);
    if (seg === "0" && !isDigit(next) && next !== ".") {
        if (d === "0") return st;
        return mk(st.t.slice(0, st.c - 1) + d + st.t.slice(st.c), st.c);
    }
    return insertRaw(st, d);
}

function inputDot(st) {
    st = dropSel(st);
    var m = /(\d*\.?\d*)$/.exec(st.t.slice(0, st.c));
    var seg = m ? m[1] : "";
    var after = /^\d*\.?/.exec(st.t.slice(st.c))[0];
    if (seg.indexOf(".") >= 0 || after.indexOf(".") >= 0) return st;
    return insertRaw(st, seg === "" ? "0." : ".");
}

function inputOperator(st, op, ctx) {
    st = dropSel(st);
    var t = st.t, c = st.c;
    var prev = t.charAt(c - 1);
    if (c === 0 || prev === "(" || prev === ";") {
        if (op === MINUS) return insertRaw(st, op);
        if (c === 0 && t === "" && ctx && ctx.hasAns) return insertRaw(st, "Ans" + op);
        return st;
    }
    if (isOperatorChar(prev)) {
        if (op === MINUS && "×÷/^".indexOf(prev) >= 0) return insertRaw(st, op);
        var start = c;
        while (start > 0 && isOperatorChar(t.charAt(start - 1))) start--;
        var head = t.slice(0, start);
        if (head === "" || head.charAt(head.length - 1) === "(") {
            if (op !== MINUS) return st;
        }
        return mk(head + op + t.slice(c), start + op.length);
    }
    if (op === "mod") return insertRaw(st, "mod");
    return insertRaw(st, op);
}

function inputPostfix(st, token) {
    if (hasSel(st)) {
        var r = selRange(st);
        var w = "(" + st.t.slice(r[0], r[1]) + ")" + token;
        return mk(st.t.slice(0, r[0]) + w + st.t.slice(r[1]), r[0] + w.length);
    }
    if (!operandEndsAt(st.t, st.c)) {
        // no base yet: leave a placeholder before the exponent and park the caret in it
        if (token.charAt(0) === "^") return insertRaw(st, token, 0);
        return st;
    }
    return insertRaw(st, token);
}

function inputTemplateOp(st, op) {
    if (hasSel(st)) {
        var r = selRange(st);
        var w = "(" + st.t.slice(r[0], r[1]) + ")" + op + "()";
        return mk(st.t.slice(0, r[0]) + w + st.t.slice(r[1]), r[0] + w.length - 1);
    }
    if (!operandEndsAt(st.t, st.c)) {
        if (op === "/") return insertRaw(st, "()/()", 1);
        return insertRaw(st, op + "()", 0);
    }
    if (operandStartsAt(st.t, st.c)) return insertRaw(st, op);
    return insertRaw(st, op + "()", op.length + 1);
}

function inputFraction(st) {
    return inputTemplateOp(st, "/");
}

function unmatchedBefore(text, c) {
    var open = 0;
    for (var i = 0; i < c; i++) {
        var ch = text.charAt(i);
        if (ch === "(") open++;
        else if (ch === ")" && open > 0) open--;
    }
    return open;
}

function inputClose(st) {
    st = dropSel(st);
    var t = st.t, c = st.c;
    if (t.charAt(c) === ")") return mk(t, c + 1);
    if (unmatchedBefore(t, c) > 0) {
        if (!operandEndsAt(t, c)) return st;
        return insertRaw(st, ")");
    }
    if (c > 0 && operandEndsAt(t, c)) return mk("(" + t.slice(0, c) + ")" + t.slice(c), c + 2);
    return st;
}

function smartParen(st) {
    if (hasSel(st)) return insertOpening(st, "(", false);
    var t = st.t, c = st.c;
    if (operandEndsAt(t, c) && (t.charAt(c) === ")" || unmatchedBefore(t, c) > 0)) return inputClose(st);
    return insertOpening(st, "(", false);
}

function matchingClose(text, open) {
    var depth = 0;
    for (var i = open; i < text.length; i++) {
        var ch = text.charAt(i);
        if (ch === "(") depth++;
        else if (ch === ")") {
            depth--;
            if (depth === 0) return i;
        }
    }
    return -1;
}

// Start of the construct an opening "(" at index i belongs to: a function name, "^", "/" with its numerator group.
function openerStart(text, i) {
    var tok = tokenEndingAt(text, i);
    if (tok && tok.t === "fn") return tok.s;
    if (tok && tok.t === "op" && tok.v === "^") return tok.s;
    return i;
}

function backspace(st) {
    if (hasSel(st)) return dropSel(st);
    var t = st.t, c = st.c;
    if (c === 0) return st;
    if (t.slice(0, c).slice(-5) === "^(" + MINUS + "1)") return mk(t.slice(0, c - 5) + t.slice(c), c - 5);
    var prev = t.charAt(c - 1);
    if (prev === ")") {
        // step into the group and delete its last element, like a structured editor
        return backspace(mk(t, c - 1));
    }
    if (prev === "(") {
        var open = c - 1;
        var close = matchingClose(t, open);
        var tok = tokenEndingAt(t, open);
        var template = tok && tok.t === "op" && (tok.v === "/" || tok.v === "^");
        if (close === c) {
            // empty group: remove it with its opener ("sin()", "^()", "/()" or "()")
            if (tok && tok.t === "op" && tok.v === "/") {
                var unwrapped = unwrapNumerator(t.slice(0, tok.s));
                return mk(unwrapped.text + t.slice(close + 1), unwrapped.caret);
            }
            var from = (tok && (tok.t === "fn" || template)) ? tok.s : open;
            return mk(t.slice(0, from) + t.slice(close + 1), from);
        }
        // at the start of a denominator or exponent: go back to the numerator or base
        if (template) return mk(t, snapCaret(t, tok.s));
        // at the start of a function or group: unwrap it (sin(30) → 30)
        var start = (tok && tok.t === "fn") ? tok.s : open;
        if (close > 0) return mk(t.slice(0, start) + t.slice(c, close) + t.slice(close + 1), start);
        return mk(t.slice(0, start) + t.slice(c), start);
    }
    var tk = tokenEndingAt(t, c);
    if (tk && (tk.t === "fn" || tk.t === "ans" || (tk.t === "op" && tk.v === "mod") || (tk.t === "const" && tk.e - tk.s > 1))) {
        return mk(t.slice(0, tk.s) + t.slice(c), tk.s);
    }
    if (prev === "/" && t.charAt(c) === "") {
        var u = unwrapNumerator(t.slice(0, c - 1));
        return mk(u.text, u.caret);
    }
    var cut = c - 1;
    // a two-character glyph such as ⁻¹
    if (t.slice(c - 2, c) === INV) cut = c - 2;
    return mk(t.slice(0, cut) + t.slice(c), cut);
}

// "(1+2)" left behind by deleting a fraction bar goes back to "1+2"
function unwrapNumerator(head) {
    if (head.charAt(head.length - 1) === ")") {
        var depth = 0;
        for (var i = head.length - 1; i >= 0; i--) {
            var ch = head.charAt(i);
            if (ch === ")") depth++;
            else if (ch === "(") {
                depth--;
                if (depth === 0) {
                    var tok = tokenEndingAt(head, i);
                    if (tok && (tok.t === "fn" || (tok.t === "op" && tok.v === "^"))) break;
                    var inner = head.slice(i + 1, head.length - 1);
                    var text = head.slice(0, i) + inner;
                    return { text: text, caret: text.length };
                }
            }
        }
    }
    return { text: head, caret: head.length };
}

function deleteForward(st) {
    if (hasSel(st)) return dropSel(st);
    var t = st.t, c = st.c;
    if (c >= t.length) return st;
    var tk = tokenStartingAt(t, c);
    if (tk && (tk.t === "fn" || tk.t === "ans" || (tk.t === "op" && tk.v === "mod") || (tk.t === "const" && tk.e - tk.s > 1))) {
        var end = tk.e;
        if (tk.t === "fn" && t.charAt(end) === "(") {
            var close = matchingClose(t, end);
            if (close === end + 1) end = close + 1;
            else if (close > 0) return mk(t.slice(0, c) + t.slice(end + 1, close) + t.slice(close + 1), c);
            else end++;
        }
        return mk(t.slice(0, c) + t.slice(end), c);
    }
    if (t.charAt(c) === "(" && t.charAt(c + 1) === ")") return mk(t.slice(0, c) + t.slice(c + 2), c);
    var n = t.slice(c, c + 2) === INV ? 2 : 1;
    return mk(t.slice(0, c) + t.slice(c + n), c);
}

function normalizeInput(text) {
    var s = String(text).split("=")[0].replace(/ /g, " ");
    s = s.replace(/\*\*/g, "^");
    s = s.replace(/(\d),(\d{3})(?!\d)/g, "$1$2").replace(/,/g, ".");
    s = s.replace(/\*/g, "×").replace(/[\-–]/g, MINUS).replace(/:/g, "÷");
    s = s.replace(/²/g, "^2").replace(/³/g, "^3");
    s = s.replace(/[\[{]/g, "(").replace(/[\]}]/g, ")");
    s = s.replace(/\\?sqrt/gi, "√").replace(/\\?cbrt/gi, "∛").replace(/\\?pi/gi, "π");
    s = s.replace(/\\cdot|\\times/g, "×").replace(/\\div/g, "÷");
    s = s.replace(/\s+/g, "");
    return s;
}

function insertText(st, text) {
    var s = normalizeInput(text);
    if (s === "") return st;
    return insertRaw(st, s);
}

function isValidInput(text) {
    var s = normalizeInput(text);
    if (s === "" || s.length > 256) return false;
    var toks = tokenize(s);
    for (var i = 0; i < toks.length; i++) if (toks[i].t === "err") return false;
    return true;
}

// Letters typed before the caret (with an optional leading backslash).
function letterRun(text, c) {
    var i = c;
    while (i > 0 && isLetter(text.charAt(i - 1))) i--;
    var slash = i > 0 && text.charAt(i - 1) === "\\";
    return { start: slash ? i - 1 : i, word: text.slice(i, c), slash: slash };
}

function wordExtends(word, dict) {
    var w = word.toLowerCase();
    for (var key in dict) {
        if (key.length > w.length && key.indexOf(w) === 0) return true;
    }
    return false;
}

function isWordPrefix(word, dict) {
    var w = word.toLowerCase();
    for (var key in dict) {
        if (key.indexOf(w) === 0) return true;
    }
    return false;
}

// A complete function name still waiting for its "(" (sin could become sinh) is turned into "sin(" as soon as
// the next character cannot extend it.
function commitPendingFunction(st, nextChar) {
    var run = letterRun(st.t, st.c);
    if (run.slash || run.word === "") return st;
    for (var k = run.word.length; k >= 1; k--) {
        var w = run.word.slice(-k);
        var info = lookupWord(w);
        if (info && info.fn && !(nextChar && isLetter(nextChar) && isWordPrefix(w + nextChar, WORDS))) {
            var start = st.c - k;
            var cleared = mk(st.t.slice(0, start) + st.t.slice(st.c), start);
            return insertOpening(cleared, w + "(", false);
        }
        if (info) break;
    }
    return st;
}

// Turn a complete word before the caret into its symbol: pi → π, sqrt → √(), ans → Ans, sin → sin() ...
function resolveWord(st) {
    var run = letterRun(st.t, st.c);
    if (run.word === "") return st;
    if (run.slash) {
        var cmd = run.word.toLowerCase();
        if (LATEX.hasOwnProperty(cmd) && !wordExtends(cmd, LATEX)) {
            var cleared = mk(st.t.slice(0, run.start) + st.t.slice(st.c), run.start);
            var rep = LATEX[cmd];
            if (rep === "frac") return insertRaw(cleared, "()/()", 1);
            if (rep.charAt(rep.length - 1) === "(") return insertOpening(cleared, rep, fnSingleArg(rep));
            return insertRaw(cleared, rep);
        }
        return st;
    }
    for (var k = run.word.length; k >= 1; k--) {
        var w = run.word.slice(-k);
        var info = lookupWord(w);
        if (!info) continue;
        if (wordExtends(w, WORDS)) return st;
        var start = st.c - k;
        var base = mk(st.t.slice(0, start) + st.t.slice(st.c), start);
        if (info.c === "π") return insertRaw(base, "π");
        if (info.ans) return insertRaw(base, "Ans");
        if (info.fn) {
            var token = info.fn === "sqrt" ? "√(" : (info.fn === "cbrt" ? "∛(" : w.toLowerCase() + "(");
            if (info.fn === "nCr") token = "nCr(";
            if (info.fn === "nPr") token = "nPr(";
            return insertOpening(base, token, FN[info.fn][0] === 1);
        }
        return st;
    }
    return st;
}

var CHAR_MAP = {
    "*": "×", "·": "×", "-": MINUS, "–": MINUS, ":": "÷", ",": ".",
    "[": "(", "{": "(", "]": ")", "}": ")"
};

// One typed character, with the keyboard conveniences: operators normalised, words resolved, templates.
function typeChar(st, ch, ctx) {
    ctx = ctx || {};
    if (CHAR_MAP.hasOwnProperty(ch)) ch = CHAR_MAP[ch];
    if (ch === "=" || ch === "\n" || ch === "\r") return { st: st, equals: true };
    if (/\s/.test(ch)) return { st: st };
    if (ch === "x" && !ctx.evaluated && operandEndsAt(st.t, st.c) && !isLetter(st.t.charAt(st.c - 1))) ch = "×";
    var operandStart = isDigit(ch) || ch === "." || ch === "(" || ch === "π" || ch === "√" || ch === "∛" || ch === "|";
    if (operandStart && !ctx.evaluated) {
        var committed = commitPendingFunction(st, ch);
        // "sin" followed by "(" only needed its own parenthesis
        if (ch === "(" && committed.t !== st.t) return { st: committed };
        st = committed;
    }
    if (isDigit(ch)) {
        var prevChar = st.t.charAt(st.c - 1);
        if (prevChar === "E" || /E[−+]$/.test(st.t.slice(0, st.c))) return { st: insertRaw(st, ch) };
        return act(st, "digit", ch, ctx);
    }
    if (ch === ".") return act(st, "dot", null, ctx);
    if (ch === "+" || ch === MINUS || ch === "×" || ch === "÷") {
        if (ch === MINUS && /E$/.test(st.t.slice(0, st.c)) && !hasSel(st)) return { st: insertRaw(st, MINUS) };
        return act(st, "op", ch, ctx);
    }
    if (ch === "/") return act(st, "frac", null, ctx);
    if (ch === "^") return act(st, "pow", null, ctx);
    if (ch === "(") return act(st, "open", null, ctx);
    if (ch === ")") return act(st, "close", null, ctx);
    if (ch === "!" || ch === "%") return act(st, "postfix", ch, ctx);
    if (ch === "²") return act(st, "postfix", "^2", ctx);
    if (ch === "³") return act(st, "postfix", "^3", ctx);
    if (ch === "π") return act(st, "const", ch, ctx);
    if (ch === "√") return act(st, "fn", "√(", ctx);
    if (ch === "∛") return act(st, "fn", "∛(", ctx);
    if (ch === "|") return act(st, "fn", "abs(", ctx);
    if (ch === ";") return { st: insertRaw(st, ";") };
    if (ch === "E" && operandEndsAt(st.t, st.c) && /\d$/.test(st.t.slice(0, st.c))) return { st: insertRaw(st, "E") };
    if (ch === "\\" || isLetter(ch)) {
        if (ctx.evaluated) st = mk("", 0);
        var lower = ch === "\\" ? ch : ch.toLowerCase();
        var run = letterRun(st.t, st.c);
        if (lower !== "\\" && !run.slash && run.word !== "" && !isWordPrefix(run.word + lower, WORDS)) st = commitPendingFunction(st, lower);
        st = insertRaw(st, lower);
        return { st: resolveWord(st) };
    }
    return { st: st };
}

// ---------------------------------------------------------------- typeset layout

// metrics: {w(str) -> advance width in em, asc, desc (font ascent/descent in em)}.
function layout(text, opts) {
    var M = opts.metrics;
    var base = opts.size || 20;
    var minSize = base * 0.5;
    var tree = parse(text);
    var src = String(text);

    function box() {
        return { w: 0, a: 0, d: 0, g: [], r: [], l: [], h: [], s: [] };
    }

    function stopAt(i, x, size, p, dy) {
        dy = dy || 0;
        return { i: i, x: x, top: dy - size * 0.86, bot: dy + size * 0.26, p: p };
    }

    function put(dst, srcBox, dx, dy) {
        var k;
        for (k = 0; k < srcBox.g.length; k++) {
            var g = srcBox.g[k];
            dst.g.push({ x: g.x + dx, by: g.by + dy, size: g.size, str: g.str, role: g.role, italic: g.italic, sy: g.sy, cy: g.cy, w: g.w, s: g.s, e: g.e });
        }
        for (k = 0; k < srcBox.r.length; k++) {
            var r = srcBox.r[k];
            dst.r.push({ x: r.x + dx, y: r.y + dy, w: r.w, h: r.h, role: r.role });
        }
        for (k = 0; k < srcBox.l.length; k++) {
            var l = srcBox.l[k];
            dst.l.push({ x1: l.x1 + dx, y1: l.y1 + dy, x2: l.x2 + dx, y2: l.y2 + dy, t: l.t });
        }
        for (k = 0; k < srcBox.h.length; k++) {
            var h = srcBox.h[k];
            dst.h.push({ x: h.x + dx, y: h.y + dy, w: h.w, hh: h.hh });
        }
        for (k = 0; k < srcBox.s.length; k++) {
            var s = srcBox.s[k];
            dst.s.push({ i: s.i, x: s.x + dx, top: s.top + dy, bot: s.bot + dy, p: s.p });
        }
        dst.a = Math.max(dst.a, srcBox.a - dy);
        dst.d = Math.max(dst.d, srcBox.d + dy);
        dst.w = Math.max(dst.w, dx + srcBox.w);
    }

    function append(row, b, gapBefore) {
        put(row, b, row.w + (gapBefore || 0), 0);
    }

    function glyph(str, size, role, s, e, opt) {
        opt = opt || {};
        size = Math.max(1, Math.round(size));
        var b = box();
        var w = M.w(str) * size + (opt.italic ? size * 0.04 : 0);
        b.w = w;
        b.a = size * 0.74;
        b.d = size * 0.22;
        b.g.push({ x: 0, by: 0, size: size, str: str, role: role, italic: !!opt.italic, sy: 1, w: w, s: s, e: e });
        if (s >= 0) {
            b.s.push(stopAt(s, 0, size, 1));
            b.s.push(stopAt(e, w, size, 2));
        }
        return b;
    }

    function hiddenMark(s, e, size, p1, p2) {
        var b = box();
        if (s >= 0) {
            b.s.push(stopAt(s, 0, size, p1 === undefined ? 1 : p1));
            b.s.push(stopAt(e, 0, size, p2 === undefined ? 2 : p2));
        }
        return b;
    }

    function stretchy(str, size, role, s, e, a, d) {
        var b = glyph(str, size, role, s, e);
        var h = a + d;
        var natural = size * 1.0;
        var g = b.g[0];
        if (h > natural * 1.05) {
            g.sy = h / natural;
            var center = (d - a) / 2;
            g.cy = center;
            b.a = a + size * 0.04;
            b.d = d + size * 0.04;
            for (var k = 0; k < b.s.length; k++) {
                b.s[k].top = -a;
                b.s[k].bot = d;
            }
        }
        if (g.cy === undefined) g.cy = null;
        return b;
    }

    function placeholder(at, size) {
        var b = box();
        var w = size * 0.52, a = size * 0.66, d = size * 0.06;
        b.w = w + size * 0.08;
        b.a = a;
        b.d = d;
        b.h.push({ x: size * 0.04, y: -a, w: w, hh: a + d });
        b.s.push({ i: at, x: size * 0.04 + w / 2, top: -a - size * 0.06, bot: d + size * 0.06, p: 3 });
        return b;
    }

    function stripParen(n) {
        return n.k === "paren" ? n.inner : n;
    }

    // a group whose parentheses are hidden (fraction parts, exponents, radicands): its "(" and ")" become
    // zero-width caret marks at the content edges
    function hiddenGroup(n, size) {
        if (n.k !== "paren") return lay(n, size);
        var row = box();
        append(row, hiddenMark(n.s, n.s + 1, size, 0.5, 2));
        append(row, lay(n.inner, size));
        if (n.closed) append(row, hiddenMark(n.e - 1, n.e, size, 1, 0.5));
        row.a = Math.max(row.a, size * 0.5);
        return row;
    }

    function number(n, size) {
        var row = box();
        var text = n.text;
        var ePos = text.indexOf("E");
        var mant = ePos >= 0 ? text.slice(0, ePos) : text;
        var intLen = mant.indexOf(".") >= 0 ? mant.indexOf(".") : mant.length;
        var groups = opts.group !== false && intLen >= 5;
        for (var i = 0; i < mant.length; i++) {
            var gap = 0;
            if (groups && i > 0 && i < intLen && (intLen - i) % 3 === 0) gap = size * 0.2;
            append(row, glyph(mant.charAt(i), size, "num", n.s + i, n.s + i + 1), gap);
        }
        if (ePos >= 0) {
            append(row, glyph("×10", size, "num", n.s + ePos, n.s + ePos + 1), size * 0.08);
            var sup = box();
            var small = Math.max(minSize, size * 0.7);
            var rest = text.slice(ePos + 1);
            if (rest === "") append(sup, placeholder(n.s + ePos + 1, small));
            for (var j = 0; j < rest.length; j++) {
                var ch = rest.charAt(j) === "-" ? MINUS : rest.charAt(j);
                append(sup, glyph(ch, small, "num", n.s + ePos + 1 + j, n.s + ePos + 2 + j));
            }
            put(row, sup, row.w + size * 0.02, -size * 0.42);
        }
        return row;
    }

    function fraction(l, r, os, oe, size) {
        var inner = size > minSize * 1.2 ? Math.max(minSize, size * 0.86) : size;
        var numBox = hiddenGroup(l, inner);
        var denBox = hiddenGroup(r, inner);
        // the "/" itself: end of the numerator, start of the denominator
        put(numBox, hiddenMark(os, os, inner, 1, 0), numBox.w, 0);
        var denStart = box();
        denStart.s.push(stopAt(oe, 0, inner, 2));
        put(denBox, denStart, 0, 0);
        var pad = size * 0.12, th = Math.max(1, size * 0.055), axis = size * 0.28, gap = size * 0.14;
        var W = Math.max(numBox.w, denBox.w) + pad * 2;
        var out = box();
        var margin = size * 0.06;
        out.r.push({ x: margin, y: -axis - th / 2, w: W, h: th, role: "rule" });
        put(out, numBox, margin + (W - numBox.w) / 2, -axis - th / 2 - gap - numBox.d);
        put(out, denBox, margin + (W - denBox.w) / 2, -axis + th / 2 + gap + denBox.a);
        out.w = W + margin * 2;
        var start = nodeStart(l);
        out.s.push(stopAt(start, 0, size, 1.5));
        if (r.k === "paren" && r.closed) out.s.push(stopAt(r.e, out.w, size, 2.5));
        return out;
    }

    function radical(n, size) {
        var isRoot = n.name === "root";
        var small = Math.max(minSize, size * 0.55);
        var radNode = isRoot ? n.args[1] : n.args[0];
        if (!radNode) radNode = { k: "miss", at: n.rp >= 0 ? n.rp : nodeEnd(n) };
        var rad = lay(radNode, size);
        var radStart = isRoot ? (n.seps.length ? n.seps[0] + 1 : -1) : (n.lp >= 0 ? n.lp + 1 : -1);
        if (radStart >= 0) {
            var lead = box();
            lead.s.push(stopAt(radStart, 0, size, 2.2));
            put(rad, lead, 0, 0);
        }
        var indexBox = null;
        if (n.name === "cbrt") indexBox = glyph("3", small, "num", -1, -1);
        if (isRoot) {
            indexBox = lay(n.args[0], small);
            var idxLead = box();
            if (n.lp >= 0) idxLead.s.push(stopAt(n.lp + 1, 0, small, 2.2));
            put(indexBox, idxLead, 0, 0);
            if (n.seps.length) put(indexBox, hiddenMark(n.seps[0], n.seps[0], small, 1, 0), indexBox.w, 0);
        }
        var g = size * 0.12, th = Math.max(1, size * 0.06);
        var top = -(Math.max(rad.a, size * 0.7) + g), bot = Math.max(rad.d, size * 0.2);
        var H = bot - top;
        var ix = indexBox ? Math.max(0, indexBox.w - size * 0.2) : 0;
        var ax = ix, ay = bot - H * 0.42;
        var bx = ix + size * 0.24, by = bot;
        var cx = ix + size * 0.5, cy = top;
        var rx = cx + size * 0.1;
        var out = box();
        out.l.push({ x1: ax, y1: ay, x2: ax + size * 0.08, y2: ay - size * 0.05, t: th });
        out.l.push({ x1: ax + size * 0.08, y1: ay - size * 0.05, x2: bx, y2: by, t: th * 1.4 });
        out.l.push({ x1: bx, y1: by, x2: cx, y2: cy, t: th });
        out.r.push({ x: cx - th * 0.3, y: cy - th / 2, w: rad.w + (rx - cx) + size * 0.08, h: th, role: "rule" });
        if (indexBox) put(out, indexBox, 0, ay - size * 0.08 - indexBox.d);
        put(out, rad, rx, 0);
        out.w = rx + rad.w + size * 0.12;
        out.a = Math.max(out.a, -top + th);
        out.d = Math.max(out.d, bot + th);
        out.s.push(stopAt(n.ns, 0, size, 1));
        if (n.rp >= 0) {
            out.s.push(stopAt(n.rp, rx + rad.w, size, 1));
            out.s.push(stopAt(n.rp + 1, out.w, size, 2.5));
        }
        return out;
    }

    function delimited(n, size, left, right, inner) {
        var row = box();
        var content = inner || lay(n.args[0], size);
        var a = Math.max(content.a, size * 0.74), d = Math.max(content.d, size * 0.22);
        var lb = stretchy(left, size, "delim", n.ns, n.lp >= 0 ? n.lp + 1 : n.ne, a, d);
        append(row, lb);
        append(row, content, size * 0.04);
        if (n.rp >= 0) append(row, stretchy(right, size, "delim", n.rp, n.rp + 1, a, d), size * 0.04);
        else if (opts.ghost !== false) append(row, stretchy(right, size, "ghost", -1, -1, a, d), size * 0.04);
        return row;
    }

    function fnName(n, size) {
        var row = box();
        var label = { "nPr": "P" }[n.name] || n.name;
        var nameBox = glyph(label, size, "fn", n.ns, n.ne);
        if (n.inv) {
            nameBox.s = nameBox.s.filter(function (s) { return s.p !== 2; });
            append(row, nameBox);
            var sup = glyph(MINUS + "1", Math.max(minSize, size * 0.62), "fn", -1, -1);
            put(row, sup, row.w + size * 0.02, -size * 0.4);
            row.s.push(stopAt(n.ne, row.w, size, 2));
            return row;
        }
        return nameBox;
    }

    function args(n, size, list, from) {
        var row = box();
        for (var i = from; i < list.length; i++) {
            if (i > from) {
                var sep = n.seps[i - 1];
                append(row, glyph(";", size, "op", sep, sep + 1), size * 0.02);
                append(row, box(), size * 0.18);
            }
            append(row, lay(list[i], size));
        }
        return row;
    }

    function parenRow(n, size, inner, openS, openE) {
        var a = Math.max(inner.a, size * 0.74), d = Math.max(inner.d, size * 0.22);
        var row = box();
        append(row, stretchy("(", size, "delim", openS, openE, a, d));
        append(row, inner, size * 0.04);
        if (n.rp >= 0) append(row, stretchy(")", size, "delim", n.rp, n.rp + 1, a, d), size * 0.04);
        else if (opts.ghost !== false) append(row, stretchy(")", size, "ghost", -1, -1, a, d), size * 0.04);
        return row;
    }

    function func(n, size) {
        if (n.name === "sqrt" || n.name === "cbrt" || n.name === "root") return radical(n, size);
        if (!n.bare && n.name === "abs") return delimited(n, size, "|", "|");
        if (!n.bare && n.name === "floor") return delimited(n, size, "⌊", "⌋");
        if (!n.bare && n.name === "ceil") return delimited(n, size, "⌈", "⌉");
        if (!n.bare && n.name === "nCr") {
            // binomial: n over k between tall parentheses
            var small = Math.max(minSize, size * 0.86);
            var top = lay(n.args[0], small);
            var bottom = n.args.length > 1 ? lay(n.args[1], small) : placeholder(n.lp + 1, small);
            if (n.seps.length) put(top, hiddenMark(n.seps[0], n.seps[0] + 1, small, 1, 0), top.w, 0);
            var stack = box();
            var W = Math.max(top.w, bottom.w);
            var axis = size * 0.28, gap = size * 0.1;
            put(stack, top, (W - top.w) / 2, -axis - gap - top.d);
            var bStart = box();
            if (n.seps.length) bStart.s.push(stopAt(n.seps[0] + 1, 0, small, 2));
            put(bottom, bStart, 0, 0);
            put(stack, bottom, (W - bottom.w) / 2, -axis + gap + bottom.a);
            stack.w = W;
            var shell = { lp: n.lp, rp: n.rp, ns: n.ns, ne: n.ne, args: [] };
            var out = delimited(shell, size, "(", ")", stack);
            out.s.push(stopAt(n.ns, 0, size, 1));
            return out;
        }
        var row = box();
        if (!n.bare && n.name === "log" && n.args.length === 2) {
            append(row, glyph("log", size, "fn", n.ns, n.ne));
            var sub = lay(n.args[0], Math.max(minSize, size * 0.62));
            var subStart = box();
            subStart.s.push(stopAt(n.lp + 1, 0, Math.max(minSize, size * 0.62), 2.2));
            put(sub, subStart, 0, 0);
            put(sub, hiddenMark(n.seps[0], n.seps[0] + 1, Math.max(minSize, size * 0.62), 1, 0), sub.w, 0);
            put(row, sub, row.w + size * 0.02, size * 0.28);
            var argBox = lay(n.args[1], size);
            var argStart = box();
            argStart.s.push(stopAt(n.seps[0] + 1, 0, size, 2.2));
            put(argBox, argStart, 0, 0);
            append(row, parenRow(n, size, argBox, -1, -1), size * 0.04);
            row.s.push(stopAt(n.ns, 0, size, 1));
            return row;
        }
        append(row, fnName(n, size));
        if (n.bare) {
            append(row, lay(n.args[0], size), size * 0.14);
            return row;
        }
        append(row, parenRow(n, size, args(n, size, n.args, 0), n.lp, n.lp + 1), size * 0.04);
        return row;
    }

    function lay(n, size) {
        var row, b;
        switch (n.k) {
        case "num": return number(n, size);
        case "const": return glyph(n.name, size, "const", n.s, n.e, { italic: n.name === "e" });
        case "ans": return glyph("Ans", size, "ans", n.s, n.e);
        case "err": return glyph(src.slice(n.s, n.e), size, "error", n.s, n.e);
        case "miss": return placeholder(n.at, size);
        case "seq":
            row = box();
            for (var i = 0; i < n.items.length; i++) append(row, lay(n.items[i], size), i ? size * 0.1 : 0);
            return row;
        case "neg": case "pos":
            row = box();
            append(row, glyph(n.k === "neg" ? MINUS : "+", size, "op", n.s, n.e));
            append(row, lay(n.arg, size), size * 0.04);
            return row;
        case "post":
            row = box();
            append(row, lay(n.arg, size));
            append(row, glyph(n.op, size, "op", n.s, n.e), size * 0.02);
            return row;
        case "paren":
            b = lay(n.inner, size);
            var a = Math.max(b.a, size * 0.74), d = Math.max(b.d, size * 0.22);
            row = box();
            append(row, stretchy("(", size, "delim", n.s, n.s + 1, a, d));
            append(row, b, size * 0.04);
            if (n.closed) append(row, stretchy(")", size, "delim", n.e - 1, n.e, a, d), size * 0.04);
            else if (opts.ghost !== false) append(row, stretchy(")", size, "ghost", -1, -1, a, d), size * 0.04);
            return row;
        case "pow":
            row = box();
            var baseBox = lay(n.base, size);
            append(row, baseBox);
            var small = Math.max(minSize, size * 0.68);
            var expBox = hiddenGroup(n.exp, small);
            var lead = box();
            lead.s.push(stopAt(n.oe, 0, small, 2));
            put(expBox, lead, 0, 0);
            put(row, hiddenMark(n.os, n.os, size, 1, 0), row.w, 0);
            var shift = Math.max(size * 0.4, baseBox.a - expBox.a * 0.45);
            put(row, expBox, row.w + size * 0.03, -shift);
            if (n.exp.k === "paren" && n.exp.closed) row.s.push(stopAt(n.exp.e, row.w, size, 2.5));
            return row;
        case "bin":
            if (n.op === "/") {
                if (n.l.k === "neg") {
                    row = box();
                    append(row, glyph(MINUS, size, "op", n.l.s, n.l.e));
                    append(row, fraction(n.l.arg, n.r, n.os, n.oe, size), size * 0.02);
                    return row;
                }
                return fraction(n.l, n.r, n.os, n.oe, size);
            }
            row = box();
            append(row, lay(n.l, size));
            if (n.implicit) {
                append(row, lay(n.r, size), size * 0.06);
                return row;
            }
            var label = { "+": "+", "-": MINUS, "*": "×", "÷": "÷", "mod": "mod" }[n.op];
            var space = n.op === "mod" ? size * 0.26 : size * 0.2;
            append(row, glyph(label, size, n.op === "mod" ? "fn" : "op", n.os, n.oe), space);
            append(row, lay(n.r, size), space);
            return row;
        case "fn": return func(n, size);
        }
        return box();
    }

    var root;
    if (tree.empty) {
        root = box();
        root.a = base * 0.74;
        root.d = base * 0.22;
        root.s.push(stopAt(0, 0, base, 3));
    } else {
        root = lay(tree.root, base);
    }

    var pad = base * 0.1;
    var asc = Math.max(root.a, base * 0.86) + pad;
    var desc = Math.max(root.d, base * 0.26) + pad;
    var out = {
        width: root.w + base * 0.12, height: asc + desc, baseline: asc,
        glyphs: [], rules: [], lines: [], holes: [], carets: []
    };
    var k;
    for (k = 0; k < root.g.length; k++) {
        var g = root.g[k];
        var top = asc + g.by - M.asc * g.size;
        var item = { x: g.x, y: top, size: g.size, str: g.str, role: g.role, italic: g.italic, sy: g.sy || 1, w: g.w, s: g.s, e: g.e, lineH: (M.asc + M.desc) * g.size };
        if (g.sy && g.sy !== 1) item.y = asc + g.by + (g.cy || 0) - item.lineH / 2;
        out.glyphs.push(item);
    }
    for (k = 0; k < root.r.length; k++) {
        var r = root.r[k];
        out.rules.push({ x: r.x, y: asc + r.y, w: r.w, h: r.h });
    }
    for (k = 0; k < root.l.length; k++) {
        var l = root.l[k];
        out.lines.push({ x1: l.x1, y1: asc + l.y1, x2: l.x2, y2: asc + l.y2, t: l.t });
    }
    for (k = 0; k < root.h.length; k++) {
        var h = root.h[k];
        out.holes.push({ x: h.x, y: asc + h.y, w: h.w, h: h.hh });
    }
    var n = src.length;
    var best = [];
    for (k = 0; k <= n; k++) best.push(null);
    for (k = 0; k < root.s.length; k++) {
        var s = root.s[k];
        if (s.i < 0 || s.i > n) continue;
        if (best[s.i] === null || s.p >= best[s.i].p) best[s.i] = s;
    }
    var ok = validStops(src);
    var lastSeen = { x: 0, top: -base * 0.86, bot: base * 0.26 };
    for (k = 0; k <= n; k++) {
        var b = best[k] || lastSeen;
        if (best[k]) lastSeen = best[k];
        out.carets.push(ok[k] ? { x: b.x, y: asc + b.top, h: b.bot - b.top } : null);
    }
    return out;
}

// Nearest caret position to a point of a layout.
function hitTest(lay, x, y) {
    var bestIndex = 0, bestScore = Infinity;
    for (var i = 0; i < lay.carets.length; i++) {
        var c = lay.carets[i];
        if (!c) continue;
        var dy = y < c.y ? c.y - y : (y > c.y + c.h ? y - c.y - c.h : 0);
        var score = Math.abs(x - c.x) + dy * 2.5;
        if (score < bestScore - 0.01) {
            bestScore = score;
            bestIndex = i;
        }
    }
    return bestIndex;
}
