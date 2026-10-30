"""EasyChat convention checks: the pre-commit hook runs `--staged`; by hand
it reads the working tree. Exit 1 on a violation.

FRAMEFIELD: one field of a table (view.x, frame.x) given two different new
frames. The later one wins, and code written for the first drives the
second (the message filter's glyph and the sidebar funnel were both
view.filterButton: the header layout moved the funnel).

COGTIP: no tooltip naming settings on a cog: a cogwheel says settings
by itself, and its hover is a glow on the cog.

JUMPINSIDE: Jump hangs inside its bubble, a corner on the same corner
with the offsets inward. Beside the bubble, the gap to it ended the hover
before a click (IsMouseOver skips hit insets) and it sat on the time.

BOXLINE: a function re-fonting a frame's regions skips an edit box's: its
words line follows the box, and sized again on its own it took the scale
twice (the message box drew 16 under a box at 13).

SHIPTEXT: the shipped files (code, docs, the TOC) ride in EasyFind's zips:
no em dashes, American spelling.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAKES = r"(?:CreateFrame\(|ns\.Create\w+\()"
FRAME_LOCAL = re.compile(r"^\s*local\s+(\w+)\s*=\s*" + MAKES)
FIELD_SET = re.compile(r"^\s*(\w+)\.(\w+)\s*=\s*(?:(" + MAKES + r")|(\w+)\s*$)")
SHIPPED = {".lua", ".md", ".toc"}
BRITISH = re.compile(r"(?i)\b(colour|licence|grey|centre|behaviour|favourite|recognis|organis)")


def sources(staged):
    if not staged:
        return {p.name: p.read_text(encoding="utf-8") for p in sorted(ROOT.iterdir()) if p.suffix in SHIPPED}
    names = subprocess.run(["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
                           cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
    out = {}
    for name in names:
        if Path(name).suffix in SHIPPED and "/" not in name:
            out[name] = subprocess.run(["git", "show", ":" + name], cwd=ROOT, capture_output=True,
                                       text=True, encoding="utf-8", check=True).stdout
    return out


def frame_fields(text):
    frame_locals = {m.group(1) for m in map(FRAME_LOCAL.match, text.splitlines()) if m}
    seen = {}
    for number, line in enumerate(text.splitlines(), 1):
        m = FIELD_SET.match(line)
        if not m:
            continue
        if m.group(3) or m.group(4) in frame_locals:
            seen.setdefault(m.group(1) + "." + m.group(2), []).append(number)
    return {field: lines for field, lines in seen.items() if len(lines) > 1}


JUMP_BODY = re.compile(r"^function UI:ShowChatJump\(.*?^end", re.S | re.M)
JUMP_POINT = re.compile(r'jump:SetPoint\("(\w+)",\s*row,\s*"(\w+)"(?:,\s*(-?[\d.]+),\s*(-?[\d.]+))?\)')


def jump_outside(text):
    if "_jumpSide" in text:
        return ["_jumpSide: one inside placement, no side choice"]
    body = JUMP_BODY.search(text)
    if not body:
        return []
    code = body.group(0)
    points = JUMP_POINT.findall(code)
    if code.count("SetPoint(") != len(points) or not points:
        return ["ShowChatJump anchors Jump to something other than a corner of its row"]
    bad = []
    for mine, theirs, x, y in points:
        x, y = float(x or 0), float(y or 0)
        outside = ((mine != theirs)
                   or ("RIGHT" in mine and x > 0) or ("LEFT" in mine and x < 0)
                   or ("TOP" in mine and y > 0) or ("BOTTOM" in mine and y < 0))
        if outside:
            bad.append(f'Jump at "{mine}" of the row\'s "{theirs}" ({x:g}, {y:g}) is outside the bubble')
    return bad


COG_TIP = re.compile(r'(GameTooltip:SetText|ShowChatTipDelayed|ShowHintTooltip)\(.*(_G\["SETTINGS"\]|"[^"]*\b[Ss]ettings")')


FUNC_BODY = re.compile(r"^(?:local\s+)?function\s+[\w.:]+\(.*?^end", re.S | re.M)


def box_lines(text):
    out = []
    for m in FUNC_BODY.finditer(text):
        body = m.group(0)
        if "GetRegions()" in body and ("RegisterChatFontRegion" in body or ":SetFont(" in body) \
                and '"EditBox"' not in body:
            out.append(text.count("\n", 0, m.start()) + 1)
    return out


ESC_ATTACH = re.compile(r"AttachEscClose\((\w+)")


def esc_hooks(text):
    out = []
    for m in FUNC_BODY.finditer(text):
        body = m.group(0)
        for attach in ESC_ATTACH.finditer(body):
            after = body[attach.end():]
            if re.search(re.escape(attach.group(1)) + r':SetScript\("On(Show|Hide)"', after):
                out.append(text.count("\n", 0, m.start() + attach.start()) + 1)
    return out


def cog_tips(text):
    return [n for n, line in enumerate(text.splitlines(), 1) if COG_TIP.search(line)]


def ship_text(text):
    out = []
    for n, line in enumerate(text.splitlines(), 1):
        if "\u2014" in line:
            out.append((n, "has an em dash"))
        m = BRITISH.search(line)
        if m:
            out.append((n, f'spells "{m.group(0)}" the British way'))
    return out


def main():
    staged = "--staged" in sys.argv
    problems = []
    for name, text in sources(staged).items():
        for n, why in ship_text(text):
            problems.append(f"{name}: SHIPTEXT line {n} {why}")
        if not name.endswith(".lua"):
            continue
        for field, lines in sorted(frame_fields(text).items()):
            where = ", ".join(str(n) for n in lines)
            problems.append(f"{name}: FRAMEFIELD {field} gets a new frame at lines {where}")
        for n in cog_tips(text):
            problems.append(f"{name}: COGTIP line {n} gives a cog a settings tooltip")
        for why in jump_outside(text):
            problems.append(f"{name}: JUMPINSIDE {why}")
        for n in box_lines(text):
            problems.append(f"{name}: BOXLINE line {n} re-fonts regions without skipping an edit box's")
        for n in esc_hooks(text):
            problems.append(f"{name}: ESCHOOK line {n} sets OnShow or OnHide after AttachEscClose (drops its hooks)")
    for p in problems:
        print(p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
