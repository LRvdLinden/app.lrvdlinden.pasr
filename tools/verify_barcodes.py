#!/usr/bin/env python3
"""Checks Pasr's barcode tables and encoder logic against the python-barcode library.

Run: pip install python-barcode && python3 tools/verify_barcodes.py
The encoders here mirror Shared/Barcode/BarcodeEncoder.swift line by line; the tables are read
from Shared/Barcode/BarcodeTables.swift, so a typo in the Swift tables makes this script fail.
"""
import random
import re
import sys
from pathlib import Path

import barcode
from barcode.charsets import code128 as ref128

SRC = (Path(__file__).resolve().parent.parent / "Shared/Barcode/BarcodeTables.swift").read_text()


def table(name):
    m = re.search(rf"static let {name}: \[String\] = \[(.*?)\]", SRC, re.S)
    return re.findall(r'"([01AB]+)"', m.group(1))


def string(name):
    return re.search(rf'static let {name} = "([01]+)"', SRC).group(1)


C128, C128_STOP = table("code128"), string("code128Stop")
EAN_L, EAN_G, EAN_R, PARITY = table("eanL"), table("eanG"), table("eanR"), table("eanParity")
C39 = table("code39")
C39_CHARS = re.search(r'code39Characters: \[Character\] = Array\("(.*?)"\)', SRC).group(1)
C39_EDGE = string("code39StartStop")
ITF = table("itf")


def check(d):
    s = sum(int(c) * (3 if i % 2 == 0 else 1) for i, c in enumerate(reversed(d)))
    return (10 - s % 10) % 10


def ean13(d):
    if len(d) == 12:
        d += str(check(d))
    v = [int(c) for c in d]
    bits = "101" + "".join((EAN_L if PARITY[v[0]][i - 1] == "A" else EAN_G)[v[i]] for i in range(1, 7))
    return bits + "01010" + "".join(EAN_R[v[i]] for i in range(7, 13)) + "101"


def ean8(d):
    if len(d) == 7:
        d += str(check(d))
    v = [int(c) for c in d]
    return "101" + "".join(EAN_L[x] for x in v[:4]) + "01010" + "".join(EAN_R[x] for x in v[4:]) + "101"


def code39(t):
    t = t.upper()
    return C39_EDGE + "0" + "".join(C39[C39_CHARS.index(c)] + "0" for c in t) + C39_EDGE


def itf(d, wide=3):
    if len(d) % 2:
        d = "0" + d
    bits = "1010"
    for i in range(0, len(d), 2):
        b, s = ITF[int(d[i])], ITF[int(d[i + 1])]
        for k in range(5):
            bits += "1" * (wide if b[k] == "1" else 1) + "0" * (wide if s[k] == "1" else 1)
    return bits + "1" * wide + "01"


def code128(text):
    ch = list(text)
    codes, subset, i = [], " ", 0

    def run(s):
        e = s
        while e < len(ch) and ch[e].isdigit():
            e += 1
        return e - s

    while i < len(ch):
        r = run(i)
        at_start, at_end = i == 0, i + r == len(ch)
        use_c = r >= (4 if (at_start or at_end) else 6) or (at_start and at_end and r >= 2 and r % 2 == 0)
        if use_c:
            pairs = r // 2
            if r % 2 == 1 and not at_start:
                if subset != "B":
                    codes.append(104 if subset == " " else 100)
                    subset = "B"
                codes.append(ord(ch[i]) - 32)
                i += 1
            if subset != "C":
                codes.append(105 if subset == " " else 99)
                subset = "C"
            for _ in range(pairs):
                codes.append(int(ch[i]) * 10 + int(ch[i + 1]))
                i += 2
        else:
            if subset != "B":
                codes.append(104 if subset == " " else 100)
                subset = "B"
            codes.append(ord(ch[i]) - 32)
            i += 1
    cs = codes[0] + sum(p * c for p, c in enumerate(codes) if p > 0)
    codes.append(cs % 103)
    return "".join(C128[c] for c in codes) + C128_STOP


def decode128(bits):
    """Independent decoder using the reference library's table: returns text, or raises."""
    assert bits.endswith("11000111010" + "11"), "bad stop"
    body = bits[: -13]
    assert len(body) % 11 == 0
    vals = [ref128.CODES.index(body[k:k + 11]) for k in range(0, len(body), 11)]
    data, cs = vals[:-1], vals[-1]
    assert cs == (data[0] + sum(p * c for p, c in enumerate(data) if p > 0)) % 103, "bad checksum"
    out, subset = "", {104: "B", 105: "C"}[data[0]]
    for v in data[1:]:
        if subset == "B" and v == 99:
            subset = "C"
        elif subset == "C" and v == 100:
            subset = "B"
        elif subset == "C":
            out += f"{v:02d}"
        else:
            out += chr(v + 32)
    return out


def ref(cls, value, **kw):
    return barcode.get_barcode_class(cls)(value, **kw).build()[0]


def main():
    rnd = random.Random(7)
    fails = 0
    # Tables equal the reference tables.
    assert C128 == list(ref128.CODES), "Code 128 table differs"
    for _ in range(300):
        d12 = "".join(rnd.choice("0123456789") for _ in range(12))
        if ean13(d12) != ref("ean13", d12):
            fails += 1; print("EAN-13", d12)
        d7 = "".join(rnd.choice("0123456789") for _ in range(7))
        if ean8(d7) != ref("ean8", d7):
            fails += 1; print("EAN-8", d7)
        d11 = "".join(rnd.choice("0123456789") for _ in range(11))
        if ean13("0" + d11) != ref("upca", d11):
            fails += 1; print("UPC-A", d11)
        t = "".join(rnd.choice(C39_CHARS) for _ in range(rnd.randint(1, 12)))
        if code39(t) != ref("code39", t, add_checksum=False):
            fails += 1; print("Code 39", repr(t))
        n = "".join(rnd.choice("0123456789") for _ in range(rnd.choice([2, 4, 6, 10, 14])))
        expected_itf = ref("itf", n)
        # Compare ITF by narrow/wide elements; the libraries use different module widths.
        mine = [len(m.group()) for m in re.finditer(r"1+|0+", itf(n, wide=3))]
        theirs = [len(m.group()) for m in re.finditer(r"1+|0+", expected_itf)]
        norm = lambda ws: ["W" if w > min(ws) else "N" for w in ws]
        if norm(mine) != norm(theirs):
            fails += 1; print("ITF", n)
        alphabet = "0123456789" * 4 + "ABCxyz-/. "
        s = "".join(rnd.choice(alphabet) for _ in range(rnd.randint(1, 24)))
        try:
            if decode128(code128(s)) != s:
                fails += 1; print("Code 128 roundtrip", repr(s))
        except Exception as e:  # noqa: BLE001
            fails += 1; print("Code 128", repr(s), e)
    # Known values: EAN-13 check digit of 400638133393 is 1.
    assert ean13("400638133393").endswith(EAN_R[1] + "101")
    print("OK" if fails == 0 else f"{fails} failures")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
