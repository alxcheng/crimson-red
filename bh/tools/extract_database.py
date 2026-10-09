#!/usr/bin/env python3
"""Extract Battleheart's built-in Database object from the APK's Unity data.

The whole game database (items, starting party, class powers + cooldowns,
maps/levels/waves, loot tables, XP curve) is ONE serialized MonoBehaviour
("**DATABASE") inside assets/bin/Data/level0 (Unity 4.7.2f1, little-endian).
Release builds strip type trees, so generic tools (UnityPy, AssetStudio) dump
it as an empty stub. The field layout is known from the IL, though
(il/Assembly-UnityScript.il, classes Item..Database, L606-L2556), so this
script walks the bytes by hand in declaration order:
  int32/float32 = 4 bytes; bool = 1 byte padded to 4; string = int32 length +
  UTF-8 bytes padded to 4; array = int32 count + elements.
The parse is self-checking: every length is bounds-checked and every bool must
be 0/1, and it must consume the object without error.

Usage:  python3 bh/tools/extract_database.py [path/to/level0]
Writes: bh/data/*.json (one file per table; array index = the id the game uses).
"""
import json, os, struct, sys

DEFAULT = "/Users/alexcheng/CascadeProjects/Battleheart datamine/decompiled/resources/assets/bin/Data/level0"
DATA = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
b = open(DATA, "rb").read()
class R:
    def __init__(s,pos): s.p=pos; s.ba=True
    def align(s): s.p=(s.p+3)&~3
    def i32(s): v=struct.unpack_from('<i',b,s.p)[0]; s.p+=4; return v
    def f32(s): v=struct.unpack_from('<f',b,s.p)[0]; s.p+=4; return round(v,6)
    def boolean(s):
        v=b[s.p]; s.p+=1
        if s.ba: s.align()
        assert v in (0,1), (hex(s.p), v)
        return bool(v)
    def string(s):
        n=s.i32(); assert 0<=n<5000,(hex(s.p),n)
        v=b[s.p:s.p+n].decode('utf-8'); s.p+=n; s.align(); return v
    def arr(s,fn):
        n=s.i32(); assert 0<=n<5000,(hex(s.p),n)
        return [fn() for _ in range(n)]
    def boolarr(s):
        n=s.i32(); assert 0<=n<5000,(hex(s.p),n)
        v=[bool(x) for x in b[s.p:s.p+n]]; s.p+=n; s.align(); return v
    def obj(s,spec):
        o={}
        for name,t in spec: o[name]=s.read(t)
        return o
    def read(s,t):
        if isinstance(t,list): return s.obj(t)
        if isinstance(t,tuple): return s.arr(lambda: s.read(t[0]))
        return getattr(s,t)()
ITEM=[('itemName','string'),('description','string'),('icon','string'),('itemType','string'),('power','i32'),('upgrade','i32'),('sellPrice','i32'),('usableBy','boolarr'),('ingameModel','string')]
PLAYER=[('playerName','string'),('characterClass','i32'),('level','i32'),('description','string'),('recruited','boolean'),('available','boolean'),('gear',('i32',)),('XP','i32'),('power','i32'),('defense','i32'),('maxHealth','i32'),('abilities',('i32',)),('passives',('i32',)),('icon','string')]
POWER=[('powerName','string'),('description','string'),('icon','string'),('cooldown','i32')]
PC=[('whichClass','string'),('powerScale','f32'),('defenseScale','f32'),('healthScale','i32'),('whichPower',(POWER,))]
LT=[('requiredKills','i32'),('whichTable','i32')]
WAVE=[('initialDelay','f32'),('spawnDelay','f32'),('maxEnemies','i32'),('enemies',('i32',))]
LEVEL=[('levelName','string'),('description','string'),('complete','boolean'),('arena','boolean'),('arenaTable',(LT,)),('prereq','i32'),('prereqLoc','i32'),('myPositionX','f32'),('myPositionY','f32'),('waves',(WAVE,)),('whichMap','string'),('enemySet','string'),('totalEnemyTypes','i32'),('transition','i32'),('transitionDirection','i32'),('music','string'),('goldReward','i32'),('XPReward','i32'),('lootTable','i32'),('rareChance','i32'),('highScore','i32')]
MAP=[('mapName','string'),('mapScale','f32'),('whichLevel',(LEVEL,))]
LOOT=[('tableName','string'),('minLevel','i32'),('maxLevel','i32'),('tableContents',('i32',))]
DB=[('itemDB',(ITEM,)),('partyDB',(PLAYER,)),('powerDB',(PC,)),('inventory',('i32',)),('party',('i32',)),('reserves',('i32',)),('gold','i32'),('timePlayed','f32'),('merchant',('i32',)),('levelDB',(MAP,)),('whichSaveSlot','i32'),('currentMap','i32'),('whichLevel','i32'),('tutorial','boolean'),('firstLevelXP','i32'),('XPscale','f32'),('XPtable',('f32',)),('transferLevel','i32'),('lootTables',(LOOT,)),('academyFirstVisit','i32'),('merchantFirstVisit','i32'),('armoryFirstVisit','i32'),('keepFirstVisit','i32'),('level5reminder','i32'),('arenaExplanation','i32'),('finalBossKill','i32'),('musicEnabled','boolean'),('soundEnabled','boolean'),('freshBoot','boolean')]

# The Database's first field is itemDB; its first element is "Iron Sword".
# Back up over that string's length prefix and the array count.
start = b.index(b"Iron Sword") - 8
r = R(start)
db = r.obj(DB)
print("parsed Database: bytes 0x%x-0x%x of level0" % (start, r.p))

def dump(name, value):
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(value, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("  %-16s %s" % (name + ".json", len(value) if isinstance(value, list) else "object"))

def indexed(rows):
    return [dict(id=i, **row) for i, row in enumerate(rows)]

os.makedirs(OUT, exist_ok=True)
dump("items", indexed(db["itemDB"]))
dump("party", indexed(db["partyDB"]))
dump("classes", indexed(db["powerDB"]))
dump("maps", indexed(db["levelDB"]))
dump("loot_tables", indexed(db["lootTables"]))
tables = ("itemDB", "partyDB", "powerDB", "levelDB", "lootTables")
dump("globals", {k: v for k, v in db.items() if k not in tables})
