"""
svsim.py - a small cycle-based simulator for the synthesizable SystemVerilog
subset used in this project (single clock, 2-state, unsigned arithmetic).

SV source is parsed, elaborated (flattened), and every process is compiled to
a Python function.  Width rules follow IEEE 1800 context-determined sizing for
the operators used here.  Not a general-purpose simulator.
"""
import re, sys

# =============================================================== lexer
TOK = re.compile(r"""
 (?P<ws>\s+|//[^\n]*|/\*.*?\*/|\(\*.*?\*\))
|(?P<num>\d+'[sS]?[bBoOdDhH][ \t]*[0-9a-fA-F_xXzZ]+)
|(?P<fill>'[01])
|(?P<tick>')
|(?P<int>\d[\d_]*)
|(?P<id>[A-Za-z_][A-Za-z0-9_$]*)
|(?P<op>\+:|::|<<|>>|<=|>=|==|!=|&&|\|\||\+\+|[-+*/%&|^~!<>=?:;,.(){}\[\]@\#])
""", re.S | re.X)

def lex(src):
    out, pos = [], 0
    while pos < len(src):
        m = TOK.match(src, pos)
        if not m: raise SyntaxError(f"lex error near {src[pos:pos+40]!r}")
        pos = m.end(); k = m.lastgroup
        if k == "ws": continue
        out.append((k, m.group(k)))
    out.append(("eof", ""))
    return out

def parse_num(s):
    if "'" not in s: return int(s.replace("_", "")), 32
    w, rest = s.split("'"); rest = rest.lstrip("sS"); base = rest[0].lower(); digits = rest[1:].replace("_", "").strip()
    return int(digits, {"b": 2, "o": 8, "d": 10, "h": 16}[base]), int(w)

# =============================================================== AST (tuples)
# expr: ('id',name) ('num',val,width) ('fill',bit) ('un',op,e) ('bin',op,a,b) ('tern',c,t,f)
#       ('cat',[e]) ('idx',e,i) ('part',e,msb,lsb) ('ipart',e,base,w) ('mem',e,field)
#       ('call',name,[args]) ('cast',width_expr,e)
class Parser:
    def __init__(s, toks): s.t = toks; s.p = 0
    def peek(s, k=0): return s.t[s.p + k]
    def at(s, v): return s.t[s.p][1] == v
    def next(s): tok = s.t[s.p]; s.p += 1; return tok
    def expect(s, v):
        tok = s.next()
        if tok[1] != v: raise SyntaxError(f"expected {v!r} got {tok} near {s.t[s.p-5:s.p+5]}")
        return tok
    def accept(s, v):
        if s.at(v): s.p += 1; return True
        return False
    def ident(s):
        tok = s.next()
        if tok[0] != "id": raise SyntaxError(f"expected identifier got {tok}")
        return tok[1]

    # ---------------- top level
    def file(s):
        items = []
        while s.peek()[0] != "eof":
            if s.at("package"): items.append(s.package())
            elif s.at("module"): items.append(s.module())
            else: raise SyntaxError(f"unexpected {s.peek()}")
        return items
    def imports(s):
        out = []
        while s.accept("import"):
            name = s.ident(); s.expect("::"); s.expect("*"); s.expect(";"); out.append(name)
        return out
    def package(s):
        s.expect("package"); name = s.ident(); s.expect(";")
        body = s.items("endpackage")
        return ("package", name, body)
    def module(s):
        s.expect("module"); name = s.ident(); imps = s.imports()
        params = []
        if s.accept("#"):                         # #(parameter int W = 12, ...)
            s.expect("(")
            while not s.at(")"):
                s.accept("parameter"); s.type_() if s.peek(1)[1] != "=" else None
                pn = s.ident(); s.expect("="); params.append((pn, s.expr())); s.accept(",")
            s.expect(")")
        ports = []
        s.expect("(")
        while not s.at(")"):
            d = s.next()[1]                       # input / output
            typ = s.type_()
            pname = s.ident(); ports.append((d, typ, pname))
            s.accept(",")
        s.expect(")"); s.expect(";")
        body = s.items("endmodule")
        return ("module", name, imps, ports, body, params)

    def type_(s):
        """returns ('logic', packed_dims) | ('int',) | ('named', name)"""
        if s.accept("logic") or s.accept("bit") or s.accept("wire") or s.accept("reg"):
            dims = []
            while s.at("["):
                s.expect("["); a = s.expr(); s.expect(":"); b = s.expr(); s.expect("]"); dims.append((a, b))
            return ("logic", dims)
        if s.accept("int"): return ("int",)
        if s.peek()[0] == "id" and s.peek(1)[0] == "id": return ("named", s.ident())
        if s.peek()[0] == "id" and s.peek(1)[1] == "[" and False: pass
        return ("logic", [])

    def unpacked(s):
        dims = []
        while s.at("["):
            s.expect("["); a = s.expr()
            if s.accept(":"): b = s.expr(); dims.append(("range", a, b))
            else: dims.append(("size", a))
            s.expect("]")
        return dims

    def items(s, endkw):
        out = []
        while not s.accept(endkw):
            out.append(s.item())
        return out

    def item(s):
        v = s.peek()[1]
        if v == "import": return ("import", s.imports())
        if v == "localparam" or v == "parameter":
            s.next(); typ = s.type_() if s.peek(1)[1] != "=" else ("int",)
            name = s.ident(); s.expect("="); e = s.expr(); s.expect(";")
            return ("param", typ, name, e)
        if v == "typedef": return s.typedef()
        if v == "function": return s.function()
        if v == "assign":
            s.next(); lhs = s.lvalue(); s.expect("="); e = s.expr(); s.expect(";")
            return ("assign", lhs, e)
        if v in ("always_ff", "always"):
            s.next(); s.expect("@"); s.expect("("); s.expect("posedge"); clk = s.ident(); s.expect(")")
            return ("seq", s.stmt())
        if v == "always_comb":
            s.next(); return ("comb", s.stmt())
        # declaration or instance
        if v in ("logic", "int", "bit") or (s.peek()[0] == "id" and s.peek(1)[0] == "id" and s.peek(2)[1] != "("):
            return s.decl()
        if s.peek()[0] == "id" and ((s.peek(1)[0] == "id" and s.peek(2)[1] == "(") or s.peek(1)[1] == "#"):
            return s.instance()
        raise SyntaxError(f"unexpected item {s.peek()} {s.t[s.p:s.p+6]}")

    def decl(s):
        typ = s.type_(); names = []
        while True:
            n = s.ident(); ud = s.unpacked(); names.append((n, ud))
            if s.accept(";"): break
            s.expect(",")
        return ("decl", typ, names)

    def typedef(s):
        s.expect("typedef")
        if s.accept("enum"):
            base = s.type_(); s.expect("{"); vals = []; nxt = None
            while not s.accept("}"):
                n = s.ident(); e = None
                if s.accept("="): e = s.expr()
                vals.append((n, e)); s.accept(",")
            name = s.ident(); s.expect(";")
            return ("enum", name, base, vals)
        if s.accept("struct"):
            s.expect("packed"); s.expect("{"); fields = []
            while not s.accept("}"):
                typ = s.type_(); n = s.ident(); s.expect(";"); fields.append((typ, n))
            name = s.ident(); s.expect(";")
            return ("struct", name, fields)
        typ = s.type_(); name = s.ident(); ud = s.unpacked(); s.expect(";")
        return ("tdef", name, typ, ud)

    def function(s):
        s.expect("function"); s.accept("automatic")
        rtyp = s.type_(); name = s.ident(); s.expect("("); args = []
        while not s.at(")"):
            s.expect("input"); typ = s.type_(); an = s.ident(); args.append((typ, an)); s.accept(",")
        s.expect(")"); s.expect(";")
        decls, body = [], []
        while not s.at("endfunction"):
            if s.peek()[1] in ("logic", "int", "bit") or (s.peek()[0] == "id" and s.peek(1)[0] == "id"
                    and s.peek()[1] not in ("return", "if", "case", "unique", "for", "begin", "else")):
                decls.append(s.decl())
            else: body.append(s.stmt())
        s.expect("endfunction")
        return ("function", name, rtyp, args, decls, body)

    def instance(s):
        mod = s.ident(); ovr = []
        if s.accept("#"):                         # #(.W(12), .N(3))
            s.expect("(")
            while not s.at(")"):
                s.expect("."); pn = s.ident(); s.expect("("); ovr.append((pn, s.expr())); s.expect(")"); s.accept(",")
            s.expect(")")
        inst = s.ident(); s.expect("("); conns = []
        while not s.at(")"):
            s.expect("."); pn = s.ident(); s.expect("(")
            e = None if s.at(")") else s.expr()
            s.expect(")"); conns.append((pn, e)); s.accept(",")
        s.expect(")"); s.expect(";")
        return ("inst", mod, inst, conns, ovr)

    # ---------------- statements
    def stmt(s):
        v = s.peek()[1]
        if v == "begin":
            s.next(); out = []
            while not s.accept("end"): out.append(s.stmt())
            return ("block", out)
        if v == "if":
            s.next(); s.expect("("); c = s.expr(); s.expect(")"); a = s.stmt(); b = None
            if s.accept("else"): b = s.stmt()
            return ("if", c, a, b)
        if v in ("case", "unique", "priority"):
            if v != "case": s.next()
            s.expect("case"); s.expect("("); sel = s.expr(); s.expect(")"); items = []
            while not s.accept("endcase"):
                if s.accept("default"): s.expect(":"); items.append((None, s.stmt()))
                else:
                    labels = [s.expr()]
                    while s.accept(","): labels.append(s.expr())
                    s.expect(":"); items.append((labels, s.stmt()))
            return ("case", sel, items)
        if v == "for":
            s.next(); s.expect("("); s.accept("int"); var = s.ident(); s.expect("="); init = s.expr(); s.expect(";")
            cond = s.expr(); s.expect(";"); v2 = s.ident(); s.expect("++"); s.expect(")")
            body = s.stmt(); return ("for", var, init, cond, body)
        if v == "return":
            s.next(); e = s.expr(); s.expect(";"); return ("return", e)
        if v == ";": s.next(); return ("block", [])
        lhs = s.lvalue()
        if s.accept("<="): e = s.expr(); s.expect(";"); return ("nba", lhs, e)
        s.expect("="); e = s.expr(); s.expect(";"); return ("ba", lhs, e)

    def lvalue(s):
        e = ("id", s.ident())
        while True:
            if s.at("["): e = s.select(e)
            elif s.at(".") : s.next(); e = ("mem", e, s.ident())
            else: return e

    def select(s, e):
        s.expect("["); a = s.expr()
        if s.accept(":"): b = s.expr(); s.expect("]"); return ("part", e, a, b)
        if s.accept("+:"): w = s.expr(); s.expect("]"); return ("ipart", e, a, w)
        s.expect("]"); return ("idx", e, a)

    # ---------------- expressions (precedence climbing)
    BIN = [["||"], ["&&"], ["|"], ["^"], ["&"], ["==", "!="], ["<", "<=", ">", ">="], ["<<", ">>"],
           ["+", "-"], ["*", "/", "%"]]
    def expr(s):
        c = s.binary(0)
        if s.accept("?"):
            t = s.expr(); s.expect(":"); f = s.expr(); return ("tern", c, t, f)
        return c
    def binary(s, lvl):
        if lvl == len(s.BIN): return s.unary()
        a = s.binary(lvl + 1)
        while s.peek()[0] == "op" and s.peek()[1] in s.BIN[lvl]:
            op = s.next()[1]; b = s.binary(lvl + 1); a = ("bin", op, a, b)
        return a
    def unary(s):
        if s.peek()[0] == "op" and s.peek()[1] in ("~", "!", "-", "&", "|", "^"):
            op = s.next()[1]; return ("un", op, s.unary())
        return s.postfix(s.primary())
    def postfix(s, e):
        while True:
            if s.at("["): e = s.select(e)
            elif s.at(".") and s.peek(1)[0] == "id": s.next(); e = ("mem", e, s.ident())
            else: return e
    def primary(s):
        k, v = s.peek()
        if k == "num": s.next(); val, w = parse_num(v); return ("num", val, w)
        if k == "fill": s.next(); return ("fill", int(v[1]))
        if k == "int":
            s.next(); val = int(v.replace("_", ""))
            if s.at("'") or s.peek()[0] == "tick":
                s.next(); s.expect("("); e = s.expr(); s.expect(")"); return ("cast", ("num", val, 32), e)
            return ("num", val, 32)
        if v == "(":
            s.next(); e = s.expr(); s.expect(")")
            if s.peek()[0] == "tick":
                s.next(); s.expect("("); e2 = s.expr(); s.expect(")"); return ("cast", e, e2)
            return e
        if v == "{":
            s.next(); parts = [s.expr()]
            while s.accept(","): parts.append(s.expr())
            s.expect("}"); return ("cat", parts)
        if k == "id":
            name = s.ident()
            if s.accept("::"): name = s.ident()
            if s.at("("):
                s.next(); args = []
                while not s.at(")"):
                    args.append(s.expr()); s.accept(",")
                s.expect(")"); return ("call", name, args)
            if s.peek()[0] == "tick":                      # type'(expr)
                s.next(); s.expect("("); e = s.expr(); s.expect(")"); return ("tcast", name, e)
            return ("id", name)
        raise SyntaxError(f"unexpected token {s.peek()} near {s.t[s.p-6:s.p+6]}")

# =============================================================== types
class T:
    """packed width, unpacked dims (list of sizes), struct fields {name:(off,w)}"""
    def __init__(s, w, ud=(), fields=None, enum=None):
        s.w, s.ud, s.fields, s.enum = w, list(ud), fields, enum
    def __repr__(s): return f"T({s.w},{s.ud})"

def M(w): return (1 << w) - 1

# =============================================================== elaboration / codegen
class Scope:
    def __init__(s, parent=None):
        s.parent = parent; s.consts = {}; s.types = {}; s.funcs = {}; s.sigs = {}
    def find(s, attr, name):
        sc = s
        while sc:
            d = getattr(sc, attr)
            if name in d: return d[name]
            sc = sc.parent
        return None

class Sim:
    def __init__(s, files, top):
        items = []
        for f in files: items += Parser(lex(open(f).read())).file()
        s.pkgs = {i[1]: i for i in items if i[0] == "package"}
        s.mods = {i[1]: i for i in items if i[0] == "module"}
        s.pkg_scopes = {}
        s.V = []; s.names = {}; s.widths = []
        s.comb = []; s.seq = []          # comb: (fn, reads, writes) ; seq: fn
        s.fn_cache = {}
        s.uid = 0
        s.elab_module(top, "", None)
        s.build_sched()

    # ---------------- constants
    def const(s, e, sc):
        code, w = s.gen(e, sc, None, None)
        return eval(code, s.genv(), {"V": s.V})

    def genv(s):
        if not hasattr(s, "_genv"): s._genv = {"M": M}
        return s._genv

    def pkg_scope(s, name):
        if name in s.pkg_scopes: return s.pkg_scopes[name]
        p = s.pkgs[name]; sc = Scope(); s.pkg_scopes[name] = sc
        s.elab_items(p[2], sc, "")
        return sc

    def mk_type(s, typ, sc, ud=()):
        if typ[0] == "int": t = T(32)
        elif typ[0] == "logic":
            w = 1
            for a, b in typ[1]: w *= abs(s.const(a, sc) - s.const(b, sc)) + 1
            t = T(w)
        else:
            base = sc.find("types", typ[1])
            if base is None: raise NameError(f"unknown type {typ[1]}")
            t = T(base.w, base.ud, base.fields, base.enum)
        dims = []
        for d in ud:
            if d[0] == "size": dims.append(s.const(d[1], sc))
            else: dims.append(abs(s.const(d[1], sc) - s.const(d[2], sc)) + 1)
        if dims: t = T(t.w, dims + t.ud, t.fields, t.enum)
        return t

    def elab_items(s, items, sc, prefix):
        for it in items:
            k = it[0]
            if k == "import":
                for n in it[1]:
                    ps = s.pkg_scope(n)
                    sc.consts.update(ps.consts); sc.types.update(ps.types); sc.funcs.update(ps.funcs)
            elif k == "param":
                sc.consts[it[2]] = s.const(it[3], sc)
            elif k == "enum":
                bt = s.mk_type(it[2], sc); v = 0; vals = {}
                for n, e in it[3]:
                    if e is not None: v = s.const(e, sc)
                    sc.consts[n] = v; vals[n] = v; v += 1
                sc.types[it[1]] = T(bt.w, enum=vals)
            elif k == "struct":
                fl = [(n, s.mk_type(t, sc).w) for t, n in it[2]]
                tot = sum(w for _, w in fl); off = tot; fields = {}
                for n, w in fl: off -= w; fields[n] = (off, w)
                sc.types[it[1]] = T(tot, fields=fields)
            elif k == "tdef":
                sc.types[it[1]] = s.mk_type(it[2], sc, it[3])
            elif k == "function":
                sc.funcs[it[1]] = (it, sc)

    # ---------------- signals
    def new_sig(s, name, t):
        sid = len(s.V)
        s.V.append([0] * t.ud[0] if t.ud else 0)
        if len(t.ud) > 1: raise NotImplementedError("multi-dim unpacked")
        s.widths.append(t); s.names[name] = sid
        return sid

    def elab_module(s, mname, prefix, conns_ctx):
        m = s.mods[mname]
        sc = Scope(); sc.mod_prefix = prefix
        for n in m[2]:
            ps = s.pkg_scope(n)
            sc.consts.update(ps.consts); sc.types.update(ps.types); sc.funcs.update(ps.funcs)
        ovr = conns_ctx or {}
        for pn, e in m[5]:                        # module parameters (instance override wins)
            sc.consts[pn] = ovr[pn] if pn in ovr else s.const(e, sc)
        # first pass: typedefs/params/functions/imports
        s.elab_items([i for i in m[4] if i[0] in ("import", "param", "enum", "struct", "tdef", "function")], sc, prefix)
        ports = {}
        for d, typ, pn in m[3]:
            t = s.mk_type(typ, sc); sid = s.new_sig(prefix + pn, t); sc.sigs[pn] = (sid, t); ports[pn] = (d, sid, t)
        for it in m[4]:
            if it[0] == "decl":
                for n, ud in it[2]:
                    t = s.mk_type(it[1], sc, ud); sc.sigs[n] = (s.new_sig(prefix + n, t), t)
        for it in m[4]:
            k = it[0]
            if k == "assign": s.add_comb([("ba", it[1], it[2])], sc, f"{prefix}assign")
            elif k == "comb": s.add_comb([it[1]], sc, f"{prefix}comb")
            elif k == "seq":  s.add_seq(it[1], sc, f"{prefix}seq")
            elif k == "inst":
                child = prefix + it[2] + "."
                cports = s.elab_module(it[1], child, {pn: s.const(e, sc) for pn, e in it[4]})
                for pn, e in it[3]:
                    d, csid, ct = cports[pn]
                    if e is None: continue
                    if d == "input":
                        code, _ = s.gen(e, sc, ct.w, None)
                        s.add_raw_comb(f"V[{csid}] = ({code}) & {M(ct.w)}", s.reads_of(e, sc), {csid}, child + pn)
                    else:
                        lid, lt = sc.sigs[e[1]]
                        s.add_raw_comb(f"V[{lid}] = V[{csid}] & {M(lt.w)}", {csid}, {lid}, child + pn)
        return ports

    # ---------------- expression codegen -> (python_code, self_width)
    def lookup(s, name, sc, loc):
        if loc is not None and name in loc: return ("loc",) + loc[name]
        r = sc.find("sigs", name)
        if r: return ("sig",) + r
        c = sc.find("consts", name)
        if c is not None: return ("const", c)
        raise NameError(f"unknown identifier {name}")

    def width(s, e, sc, loc):
        k = e[0]
        if k == "num": return e[2]
        if k == "fill": return 1
        if k == "id":
            r = s.lookup(e[1], sc, loc)
            if r[0] == "const": return 32
            t = r[2]; return t.w if not t.ud else t.w
        if k == "un": return 1 if e[1] in ("!", "&", "|", "^") else s.width(e[2], sc, loc)
        if k == "bin":
            op = e[1]
            if op in ("==", "!=", "<", "<=", ">", ">=", "&&", "||"): return 1
            if op in ("<<", ">>"): return s.width(e[2], sc, loc)
            return max(s.width(e[2], sc, loc), s.width(e[3], sc, loc))
        if k == "tern": return max(s.width(e[2], sc, loc), s.width(e[3], sc, loc))
        if k == "cat": return sum(s.width(x, sc, loc) for x in e[1])
        if k == "idx":
            bt = s.etype(e[1], sc, loc)
            return bt.w if bt.ud else 1
        if k == "part": return abs(s.const(e[2], sc) - s.const(e[3], sc)) + 1
        if k == "ipart": return s.const(e[3], sc)
        if k == "mem": return s.etype(e[1], sc, loc).fields[e[2]][1]
        if k == "call": return s.func(e[1], sc)[1].w
        if k == "cast": return s.const(e[1], sc)
        if k == "tcast": return sc.find("types", e[1]).w
        raise NotImplementedError(k)

    def etype(s, e, sc, loc):
        if e[0] == "id":
            r = s.lookup(e[1], sc, loc); return r[2] if r[0] != "const" else T(32)
        if e[0] == "idx":
            bt = s.etype(e[1], sc, loc)
            if bt.ud: return T(bt.w, bt.ud[1:], bt.fields, bt.enum)
            return T(1)
        return T(s.width(e, sc, loc))

    def gen(s, e, sc, ctx, loc):
        """Python code for e evaluated in a context of width ctx (None = self)."""
        w = s.width(e, sc, loc); c = max(w, ctx or 0); k = e[0]
        if k == "num": return str(e[1] & M(e[2])), w
        if k == "fill": return ("0" if e[1] == 0 else str(M(c))), w
        if k == "id":
            r = s.lookup(e[1], sc, loc)
            if r[0] == "const": return str(r[1]), 32
            if r[0] == "loc": return r[1], w
            return f"V[{r[1]}]", w
        if k == "un":
            op = e[1]
            if op == "~": a, _ = s.gen(e[2], sc, c, loc); return f"(~({a}) & {M(c)})", w
            if op == "-": a, _ = s.gen(e[2], sc, c, loc); return f"(-({a}) & {M(c)})", w
            if op == "!": a, _ = s.gen(e[2], sc, None, loc); return f"(0 if ({a}) else 1)", 1
            aw = s.width(e[2], sc, loc); a, _ = s.gen(e[2], sc, None, loc)
            if op == "|": return f"(1 if ({a}) else 0)", 1
            if op == "&": return f"(1 if ({a}) == {M(aw)} else 0)", 1
            if op == "^": return f"(bin({a}).count('1') & 1)", 1
        if k == "bin":
            op = e[1]
            if op in ("&&", "||"):
                a, _ = s.gen(e[2], sc, None, loc); b, _ = s.gen(e[3], sc, None, loc)
                return (f"(1 if (({a}) and ({b})) else 0)" if op == "&&" else f"(1 if (({a}) or ({b})) else 0)"), 1
            if op in ("==", "!=", "<", "<=", ">", ">="):
                cw = max(s.width(e[2], sc, loc), s.width(e[3], sc, loc))
                a, _ = s.gen(e[2], sc, cw, loc); b, _ = s.gen(e[3], sc, cw, loc)
                return f"(1 if ({a}) {op} ({b}) else 0)", 1
            if op in ("<<", ">>"):
                a, _ = s.gen(e[2], sc, c, loc); b, _ = s.gen(e[3], sc, None, loc)
                if op == "<<": return f"((({a}) << ({b})) & {M(c)})", w
                return f"(({a}) >> ({b}))", w
            a, _ = s.gen(e[2], sc, c, loc); b, _ = s.gen(e[3], sc, c, loc)
            if op in ("&", "|", "^"): return f"(({a}) {op} ({b}))", w
            if op == "/": return f"(({a}) // ({b}))", w
            if op == "%": return f"(({a}) % ({b}))", w
            return f"((({a}) {op} ({b})) & {M(c)})", w
        if k == "tern":
            cc, _ = s.gen(e[1], sc, None, loc); a, _ = s.gen(e[2], sc, c, loc); b, _ = s.gen(e[3], sc, c, loc)
            return f"(({a}) if ({cc}) else ({b}))", w
        if k == "cat":
            parts = []; sh = w
            for x in e[1]:
                xw = s.width(x, sc, loc); sh -= xw; xc, _ = s.gen(x, sc, None, loc)
                parts.append(f"((({xc}) & {M(xw)}) << {sh})")
            return "(" + " | ".join(parts) + ")", w
        if k == "idx":
            bt = s.etype(e[1], sc, loc); base, _ = s.gen(e[1], sc, None, loc) if not bt.ud else (s.gen_ref(e[1], sc, loc), 0)
            i, _ = s.gen(e[2], sc, None, loc)
            if bt.ud: return f"{base}[{i}]", w
            return f"((({base}) >> ({i})) & 1)", 1
        if k == "part":
            base, _ = s.gen(e[1], sc, None, loc); lsb = s.const(e[3], sc)
            return f"((({base}) >> {lsb}) & {M(w)})", w
        if k == "ipart":
            base, _ = s.gen(e[1], sc, None, loc); i, _ = s.gen(e[2], sc, None, loc)
            return f"((({base}) >> ({i})) & {M(w)})", w
        if k == "mem":
            t = s.etype(e[1], sc, loc); off, fw = t.fields[e[2]]; base, _ = s.gen(e[1], sc, None, loc)
            return f"((({base}) >> {off}) & {M(fw)})", w
        if k == "call":
            fname, rt, args = s.func(e[1], sc)
            codes = []
            for (at, an), ae in zip(args, e[2]):
                if at.ud: codes.append(s.gen_ref(ae, sc, loc))
                else: ac, _ = s.gen(ae, sc, at.w, loc); codes.append(f"(({ac}) & {M(at.w)})")
            return f"{fname}({', '.join(codes)})", w
        if k == "cast":
            n = s.const(e[1], sc); ic, _ = s.gen(e[2], sc, max(n, s.width(e[2], sc, loc)), loc)
            return f"(({ic}) & {M(n)})", n
        if k == "tcast":
            ic, _ = s.gen(e[2], sc, w, loc); return f"(({ic}) & {M(w)})", w
        raise NotImplementedError(k)

    def gen_ref(s, e, sc, loc):
        """reference to an unpacked array object"""
        if e[0] == "id":
            r = s.lookup(e[1], sc, loc); return r[1] if r[0] == "loc" else f"V[{r[1]}]"
        if e[0] == "call": return s.gen(e, sc, None, loc)[0]
        raise NotImplementedError(e)

    def reads_of(s, e, sc, loc=None, acc=None):
        acc = set() if acc is None else acc
        if isinstance(e, tuple):
            if e[0] == "id":
                try:
                    r = s.lookup(e[1], sc, loc)
                    if r[0] == "sig": acc.add(r[1])
                except NameError: pass
            for x in e[1:]:
                if isinstance(x, (tuple, list)): s.reads_of(x, sc, loc, acc)
        elif isinstance(e, list):
            for x in e: s.reads_of(x, sc, loc, acc)
        return acc

    # ---------------- functions -> python defs
    def func(s, name, sc):
        entry = sc.find("funcs", name)
        if entry is None: raise NameError(f"unknown function {name}")
        f, fsc = entry
        key = id(f)
        if key in s.fn_cache: return s.fn_cache[key]
        pyname = f"f_{name}_{len(s.fn_cache)}"
        rt = s.mk_type(f[2], fsc); args = [(s.mk_type(t, fsc), n) for t, n in f[3]]
        s.fn_cache[key] = (pyname, rt, args)
        loc = {}
        for t, n in args: loc[n] = (f"l_{n}", t)
        lines = [f"def {pyname}({', '.join('l_' + n for _, n in args)}):"]
        for t, n in args:
            if t.ud: lines.append(f"    l_{n} = list(l_{n})")
        loc[name] = ("l__ret", rt)
        lines.append(f"    l__ret = {'[0]*' + str(rt.ud[0]) if rt.ud else '0'}")
        for d in f[4]:
            for n, ud in d[2]:
                t = s.mk_type(d[1], fsc, ud); loc[n] = (f"l_{n}", t)
                lines.append(f"    l_{n} = {'[0]*' + str(t.ud[0]) if t.ud else '0'}")
        body = []
        for st in f[5]: s.gen_stmt(st, fsc, loc, body, 1, nba=False)
        lines += body
        lines.append("    return l__ret")
        src = "\n".join(lines)
        try: exec(src, s.genv())
        except Exception: print(src); raise
        return s.fn_cache[key]

    # ---------------- statements -> python
    def lv_target(s, lhs, sc, loc):
        """returns (kind, ref, idx_code, lsb_code, width, base_type)"""
        if lhs[0] == "id":
            r = s.lookup(lhs[1], sc, loc)
            return ("whole", r, None, None, r[2].w, r[2])
        if lhs[0] == "idx":
            inner = lhs[1]
            if inner[0] == "id":
                r = s.lookup(inner[1], sc, loc); i, _ = s.gen(lhs[2], sc, None, loc)
                if r[2].ud: return ("elem", r, i, None, r[2].w, r[2])
                return ("bits", r, None, i, 1, r[2])
        if lhs[0] in ("ipart", "part"):
            inner = lhs[1]
            if lhs[0] == "ipart": lsb, _ = s.gen(lhs[2], sc, None, loc); w = s.const(lhs[3], sc)
            else: lsb = str(s.const(lhs[3], sc)); w = abs(s.const(lhs[2], sc) - s.const(lhs[3], sc)) + 1
            if inner[0] == "id":
                r = s.lookup(inner[1], sc, loc); return ("bits", r, None, lsb, w, r[2])
            if inner[0] == "idx" and inner[1][0] == "id":
                r = s.lookup(inner[1][1], sc, loc); i, _ = s.gen(inner[2], sc, None, loc)
                return ("ebits", r, i, lsb, w, r[2])
        raise NotImplementedError(f"lvalue {lhs}")

    def gen_stmt(s, st, sc, loc, out, ind, nba, writes=None):
        P = "    " * ind; k = st[0]
        if k == "block":
            if not st[1]: out.append(P + "pass")
            for x in st[1]: s.gen_stmt(x, sc, loc, out, ind, nba, writes)
        elif k == "if":
            c, _ = s.gen(st[1], sc, None, loc); out.append(f"{P}if {c}:")
            s.gen_stmt(st[2], sc, loc, out, ind + 1, nba, writes)
            if st[3] is not None:
                out.append(f"{P}else:"); s.gen_stmt(st[3], sc, loc, out, ind + 1, nba, writes)
        elif k == "case":
            sw = s.width(st[1], sc, loc); sel, _ = s.gen(st[1], sc, None, loc)
            tmp = f"_c{s.uid}"; s.uid += 1; out.append(f"{P}{tmp} = {sel}")
            first = True; has = False
            for labels, body in st[2]:
                if labels is None: continue
                conds = []
                for lab in labels:
                    cw = max(sw, s.width(lab, sc, loc)); lc, _ = s.gen(lab, sc, cw, loc)
                    conds.append(f"{tmp} == ({lc})")
                out.append(f"{P}{'if' if first else 'elif'} {' or '.join(conds)}:"); first = False; has = True
                s.gen_stmt(body, sc, loc, out, ind + 1, nba, writes)
            for labels, body in st[2]:
                if labels is None:
                    if has: out.append(f"{P}else:"); s.gen_stmt(body, sc, loc, out, ind + 1, nba, writes)
                    else: s.gen_stmt(body, sc, loc, out, ind, nba, writes)
        elif k == "for":
            var = st[1]; loc2 = dict(loc); loc2[var] = (f"l_{var}", T(32))
            init, _ = s.gen(st[2], sc, None, loc)
            out.append(f"{P}l_{var} = {init}")
            c, _ = s.gen(st[3], sc, None, loc2)
            out.append(f"{P}while {c}:")
            s.gen_stmt(st[4], sc, loc2, out, ind + 1, nba, writes)
            out.append(f"{P}    l_{var} += 1")
        elif k == "return":
            rt = loc["__fn_rt"] if "__fn_rt" in loc else None
            r = loc[[n for n in loc if loc[n][0] == "l__ret"][0]][1]
            if r.ud: c = s.gen_ref(st[1], sc, loc); out.append(f"{P}return list({c})")
            else: c, _ = s.gen(st[1], sc, r.w, loc); out.append(f"{P}return ({c}) & {M(r.w)}")
        elif k in ("nba", "ba"):
            kind, r, i, lsb, w, bt = s.lv_target(st[1], sc, loc)
            if bt.ud and kind == "whole": rhs = f"list({s.gen_ref(st[2], sc, loc)})"
            else:
                rc, _ = s.gen(st[2], sc, w, loc); rhs = f"(({rc}) & {M(w)})"
            ref = r[1] if r[0] == "loc" else f"V[{r[1]}]"
            if writes is not None and r[0] == "sig": writes.add(r[1])
            if k == "nba" and r[0] == "sig":
                sid = r[1]
                if kind == "whole": out.append(f"{P}NB.append(({sid}, None, None, 0, {rhs}))")
                elif kind == "elem": out.append(f"{P}NB.append(({sid}, {i}, None, 0, {rhs}))")
                elif kind == "bits": out.append(f"{P}NB.append(({sid}, None, {lsb}, {w}, {rhs}))")
                else: out.append(f"{P}NB.append(({sid}, {i}, {lsb}, {w}, {rhs}))")
            else:
                if kind == "whole": out.append(f"{P}{ref} = {rhs}")
                elif kind == "elem": out.append(f"{P}{ref}[{i}] = {rhs}")
                elif kind == "bits":
                    out.append(f"{P}_l = {lsb}; {ref} = ({ref} & ~({M(w)} << _l)) | ({rhs} << _l)")
                else:
                    out.append(f"{P}_l = {lsb}; _i = {i}; {ref}[_i] = ({ref}[_i] & ~({M(w)} << _l)) | ({rhs} << _l)")
        else: raise NotImplementedError(k)

    # ---------------- processes
    def add_comb(s, stmts, sc, name):
        writes = set(); body = []
        for st in stmts: s.gen_stmt(st, sc, {}, body, 1, nba=False, writes=writes)
        reads = set()
        for st in stmts: s.reads_of(st, sc, None, reads)
        reads -= set()   # self-reads allowed (blocking temp)
        src = f"def _p(V):\n" + "\n".join(body)
        s.add_src_comb(src, reads, writes, name)

    def add_raw_comb(s, code, reads, writes, name):
        s.add_src_comb(f"def _p(V):\n    {code}", reads, writes, name)

    def add_src_comb(s, src, reads, writes, name):
        env = s.genv(); loc = {}
        try: exec(src, env, loc)
        except Exception: print(src); raise
        s.comb.append((loc["_p"], reads, writes, name))

    def add_seq(s, st, sc, name):
        body = []; s.gen_stmt(st, sc, {}, body, 1, nba=True)
        src = "def _p(V, NB):\n" + "\n".join(body)
        env = s.genv(); loc = {}
        try: exec(src, env, loc)
        except Exception: print(src); raise
        s.seq.append(loc["_p"])

    def build_sched(s):
        s.readers = {}
        for ci, (fn, reads, writes, name) in enumerate(s.comb):
            for r in reads: s.readers.setdefault(r, []).append(ci)
        s.settle(all_=True)

    # ---------------- run
    def snapshot(s, sid):
        v = s.V[sid]; return list(v) if isinstance(v, list) else v

    def settle(s, changed=None, all_=False):
        V = s.V; comb = s.comb
        pending = list(range(len(comb))) if all_ else sorted({c for sid in changed for c in s.readers.get(sid, ())})
        inq = set(pending); it = 0
        while pending:
            it += 1
            if it > 200000: raise RuntimeError("combinational loop?")
            ci = pending.pop(0); inq.discard(ci)
            fn, reads, writes, name = comb[ci]
            old = [(w, s.snapshot(w)) for w in writes]
            fn(V)
            for w, o in old:
                if V[w] != o:
                    for r in s.readers.get(w, ()):
                        if r not in inq: inq.add(r); pending.append(r)

    def step(s):
        V = s.V; NB = []
        for p in s.seq: p(V, NB)
        changed = set()
        for sid, idx, lsb, w, val in NB:
            if idx is None and lsb is None:
                if V[sid] != val: V[sid] = val; changed.add(sid)
            elif lsb is None:
                if V[sid][idx] != val: V[sid][idx] = val; changed.add(sid)
            elif idx is None:
                nv = (V[sid] & ~(M(w) << lsb)) | (val << lsb)
                if nv != V[sid]: V[sid] = nv; changed.add(sid)
            else:
                nv = (V[sid][idx] & ~(M(w) << lsb)) | (val << lsb)
                if nv != V[sid][idx]: V[sid][idx] = nv; changed.add(sid)
        s.settle(changed)

    def set(s, name, val):
        sid = s.names[name]; V = s.V
        if V[sid] != val: V[sid] = val; s.settle({sid})
    def get(s, name): return s.V[s.names[name]]
