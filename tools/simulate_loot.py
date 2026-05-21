#!/usr/bin/env python3
"""Simulate event-loot drops for the PZRC mod.

Parses common/media/lua/server/Events/PZRC_EventConfig.lua, then for each
loot table rolls the same way the mod does at runtime:

    for entry in table:
        if random.random() < entry.chance:
            qty = random.randint(entry.min, entry.max)
            spawn qty copies of entry.item

Each event is rolled N times (default 3) so you can see how the table
behaves under real luck.
"""
import argparse
import random
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

MOD_LUA = Path(__file__).resolve().parents[1] / "common/media/lua/server/Events/PZRC_EventConfig.lua"


def extract_block(text: str, header: str) -> str:
    start = text.index(header)
    open_brace = text.index("{", start)
    depth = 0
    for i in range(open_brace, len(text)):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    raise ValueError(f"Unterminated block: {header}")


def parse_loot_tables(lua_text: str) -> dict[str, list[tuple[str, float, int, int]]]:
    block = extract_block(lua_text, "PZRC_EventConfig.Loot")
    out: dict[str, list] = {}
    for ev in re.finditer(r"(\w+)\s*=\s*\{", block):
        name = ev.group(1)
        if name in ("item", "min", "max", "chance", "count", "Loot"):
            continue
        i = ev.end() - 1
        depth = 0
        while i < len(block):
            if block[i] == "{":
                depth += 1
            elif block[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = block[ev.end() - 1 : i + 1]
        rows = []
        for m in re.finditer(
            r'\{\s*item\s*=\s*"([^"]+)"\s*,\s*chance\s*=\s*([0-9.]+)\s*,\s*min\s*=\s*(\d+)\s*,\s*max\s*=\s*(\d+)\s*\}',
            body,
        ):
            rows.append((m.group(1), float(m.group(2)), int(m.group(3)), int(m.group(4))))
        if rows:
            out[name] = rows
    return out


def classify(item: str) -> str:
    n = item.lower()
    if "clip" in n or "carton" in n or "box" in n or "ammostraps" in n or "bullets9mm" == n.rsplit(".", 1)[-1]:
        if "ammostraps" in n:
            return "обвес"
        return "патроны"
    if any(s in n for s in ("scope", "reddot", "laser", "gunlight", "tritium", "recoilpad", "choke")):
        return "обвес"
    if any(s in n for s in ("pistol", "revolver", "shotgun", "rifle", "carbine", "msr7t", "js14_rifle", "js3t_shotgun")):
        return "оружие"
    if any(s in n for s in (
        "tinned", "canned", "tuna", "crisps", "cereal", "sugar", "marinara", "apple",
        "cookingpot", "gridlepan", "canopener",
    )):
        return "еда/готовка"
    if any(s in n for s in (
        "water", "beer", "whiskey", "canteen",
    )):
        return "питьё"
    if any(s in n for s in ("antibiotics", "pills", "sutur", "tweezers", "disinfectant", "bandage", "splint", "scalpel")):
        return "медицина"
    if any(s in n for s in (
        "axe", "saw", "hammer", "wrench", "screwdriver", "crowbar", "machete", "shovel",
        "pipewrench", "fork", "spear", "huntingknife", "torch", "matches", "lighter",
        "rope", "twine", "tarp", "fishingrod", "trap",
    )):
        return "инструмент"
    if "book" in n or "mag" in n.rsplit(".", 1)[-1] or "magazine" in n or "notebook" in n:
        return "книги/мануалы"
    if "bag" in n:
        return "сумки"
    if any(s in n for s in ("vest", "hat", "tshirt", "hoodie", "trousers", "poncho", "gloves")):
        return "одежда"
    if any(s in n for s in ("aerosolbomb", "molotov", "flametrap", "smokebomb", "noisetrap", "gunpowder")):
        return "взрывчатка"
    if any(s in n for s in ("walkietalkie", "battery", "electronics", "wire", "carbatterycharger")):
        return "электроника"
    if any(s in n for s in ("enginepart", "petrolcan", "waterbottlepetrol", "carbattery")):
        return "запчасти"
    return "прочее"


def roll(table, rng):
    bag = Counter()
    for item, chance, mn, mx in table:
        if rng.random() < chance:
            qty = rng.randint(mn, mx)
            if qty > 0:
                bag[item] += qty
    return bag


def fmt_bag(bag):
    cats = defaultdict(list)
    for item, qty in bag.items():
        cats[classify(item)].append((item, qty))
    out_lines = []
    for cat in sorted(cats):
        items = sorted(cats[cat], key=lambda x: (-x[1], x[0]))
        line_items = ", ".join(f"{item.replace('Base.','')}×{qty}" for item, qty in items)
        out_lines.append(f"  [{cat}] {line_items}")
    return out_lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", "--rolls", type=int, default=3, help="rolls per event (default 3)")
    ap.add_argument("-s", "--seed", type=int, default=None, help="rng seed for reproducible runs")
    ap.add_argument("-e", "--event", action="append", help="restrict to one event (repeatable)")
    args = ap.parse_args()

    lua = MOD_LUA.read_text()
    tables = parse_loot_tables(lua)
    if not tables:
        print("ERROR: no loot tables parsed", file=sys.stderr)
        sys.exit(1)

    events = args.event or sorted(tables.keys())
    rng = random.Random(args.seed)

    grand_totals = defaultdict(Counter)  # event -> category -> total items across rolls

    for ev in events:
        if ev not in tables:
            print(f"!! unknown event: {ev}")
            continue
        print(f"\n========================================")
        print(f"  EVENT: {ev}  ({len(tables[ev])} entries)")
        print(f"========================================")
        for r in range(1, args.rolls + 1):
            bag = roll(tables[ev], rng)
            total = sum(bag.values())
            print(f"\n  Roll #{r} — {total} items total")
            for line in fmt_bag(bag):
                print(line)
            # update grand totals
            for item, qty in bag.items():
                grand_totals[ev][classify(item)] += qty

    print("\n========================================")
    print(f"  AGGREGATE over {args.rolls} rolls per event")
    print("========================================")
    for ev in events:
        if ev not in tables:
            continue
        totals = grand_totals[ev]
        total_items = sum(totals.values())
        avg = total_items / args.rolls
        print(f"\n  {ev}: {total_items} items across {args.rolls} rolls (avg {avg:.1f} per drop)")
        for cat in sorted(totals, key=lambda c: -totals[c]):
            print(f"    {cat:<14} {totals[cat]:>3} total  ({totals[cat]/args.rolls:.1f} avg)")


if __name__ == "__main__":
    main()
