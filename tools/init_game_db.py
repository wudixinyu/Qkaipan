#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
《卡牌大冒险》数据库构建脚本（SQLite）

作用
----
读取 data/db/schema.sql（单一源文件），按其中的 `-- @db: cfg` / `-- @db: player`
分区标记，切分成两个物理数据库文件：

    data/db/game_cfg.db     静态配置库  —— 建表 + 灌入策划配置（hero/skill/item/stage/...）
    data/db/player_save.db  玩家存档库  —— 只建表（可用 --demo 灌一份演示存档）

用法
----
    python tools/init_game_db.py                # 重建配置库 + 空存档库
    python tools/init_game_db.py --demo         # 额外灌入演示玩家数据（联调用）
    python tools/init_game_db.py --verify       # 建完顺带跑一遍结构/JSON/触发器自检
    python tools/init_game_db.py --force --demo --verify

说明
----
* 配置库每次构建都是"删档重灌"，配置的权威来源是 schema.sql + 本文件的 CONFIG_* 常量；
  后续接入 Excel/JSON 导表时，把 _seed_cfg 的数据源换成读表即可。
* 存档库只建表，绝不灌演示数据（除非显式 --demo），避免误把测试存档发给玩家。
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_FILE = ROOT / "data" / "db" / "schema.sql"
DB_DIR = ROOT / "data" / "db"
CFG_DB = DB_DIR / "game_cfg.db"
PLAYER_DB = DB_DIR / "player_save.db"

MARKER_RE = __import__("re").compile(r"^--\s*@db:\s*(cfg|player)\s*$")


# --------------------------------------------------------------------------- #
# schema.sql -> {db_name: sql_text}
# --------------------------------------------------------------------------- #
def split_schema(path: Path) -> dict[str, str]:
    if not path.exists():
        sys.exit(f"[ERR] 找不到 schema 文件: {path}")
    buckets: dict[str, list[str]] = {}
    current: str | None = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        m = MARKER_RE.match(raw.strip())
        if m:
            current = m.group(1)
            buckets.setdefault(current, [])
            continue
        if current:
            buckets[current].append(raw)
    if not buckets:
        sys.exit("[ERR] schema.sql 里没有找到 `-- @db:` 分区标记")
    return {k: "\n".join(v) for k, v in buckets.items()}


def exec_script(conn: sqlite3.Connection, sql: str) -> int:
    """按完整语句切分执行（正确处理含分号的 CREATE TRIGGER）。"""
    buf, count = "", 0
    for line in sql.splitlines(keepends=True):
        buf += line
        if sqlite3.complete_statement(buf):
            stmt = buf.strip()
            buf = ""
            if not stmt:
                continue
            conn.execute(stmt)
            count += 1
    if buf.strip():
        conn.execute(buf)
        count += 1
    return count


# --------------------------------------------------------------------------- #
# 静态配置数据（权威来源；后续可换成 Excel/JSON 导表）
# --------------------------------------------------------------------------- #
ART = "res://assets/art"
FRAME = {1: f"{ART}/frames/frame_r.png", 2: f"{ART}/frames/frame_sr.png",
         3: f"{ART}/frames/frame_ssr.png", 4: f"{ART}/frames/frame_ur.png"}

# hero_id, name, quality(1R/2SR/3SSR/4UR), element(1水2火3风4地5光6暗),
# job(1前排2输出3辅助4刺客), hp, atk, def, mres, spd, skills, portrait_file
CONFIG_HEROES = [
    (1001, "苍岚盾卫", 1, 4, 1, 5200, 320, 480, 300, 96, [4001, 4002], "char_knight"),
    (1002, "明心祭司", 2, 5, 3, 4100, 380, 260, 420, 102, [4003, 4004], "char_priest"),
    (1003, "炎狱术士", 3, 2, 2, 3600, 760, 180, 320, 108, [4005, 4006], "char_pyromancer"),
    (1004, "疾风游侠", 2, 3, 4, 3900, 700, 220, 260, 124, [4007, 4008], "char_ranger"),
]

# skill_id, name, type(1主动2被动3追击), target(1单体敌2全体敌3己方单4己方全5自身), power, cd, energy
CONFIG_SKILLS = [
    (4001, "磐石壁", 1, 4, 8000, 3, 40),
    (4002, "不动如山", 2, 5, 1500, 0, 0),
    (4003, "灵疗术", 1, 4, 6000, 2, 35),
    (4004, "明心祝福", 1, 3, 4000, 3, 30),
    (4005, "焚天业火", 1, 2, 9000, 4, 60),
    (4006, "炎心灼魂", 2, 5, 2000, 0, 0),
    (4007, "破空箭", 1, 1, 12000, 3, 45),
    (4008, "风影疾行", 3, 5, 3000, 0, 0),
]

# item_id, name, type(1装备2材料3消耗4碎片5礼包), quality, max_stack
CONFIG_ITEMS = [
    (3001, "精铁", 2, 1, 9999),
    (3002, "灵石", 2, 1, 9999),
    (3003, "苍岚盾卫碎片", 4, 2, 999),
    (3004, "金币袋", 5, 1, 99),
    (3101, "苍岚护盾", 1, 2, 1),
    (3102, "玄天法杖", 1, 3, 1),
    (3103, "炎心法珠", 1, 3, 1),
    (3104, "疾风短刃", 1, 2, 1),
]

CONFIG_CHAPTERS = [
    (1, "初入仙途", 1, 1),
    (2, "山门试炼", 2, 10),
    (3, "云天幻境", 3, 20),
]

# 22 张关卡 / 3 章：第 1 关 8 张卡、第 3 关带引导线（pre_stage_id 串成链）
CONFIG_STAGE_COUNT = {1: 8, 2: 7, 3: 7}

CONFIG_MONSTER_GROUPS = [
    (1, "山道游魂", [{"hero_id": 1004, "level": 2, "star": 1, "pos": 2}]),
    (2, "幻境精英·双卫", [{"hero_id": 1001, "level": 4, "star": 1, "pos": 1},
                     {"hero_id": 1002, "level": 4, "star": 1, "pos": 3}]),
    (3, "迷雾之主", [{"hero_id": 1003, "level": 10, "star": 2, "pos": 2},
                 {"hero_id": 1001, "level": 8, "star": 1, "pos": 1},
                 {"hero_id": 1002, "level": 8, "star": 1, "pos": 4}]),
]

# drop_group_id, item_id, weight(千分比), min, max, guaranteed
CONFIG_DROPS = [
    (1, 3002, 700, 10, 30, 1),
    (1, 3001, 250, 1, 3, 0),
    (1, 3003, 50, 1, 1, 0),
    (2, 3002, 500, 30, 60, 1),
    (2, 3101, 200, 1, 1, 0),
    (2, 3102, 200, 1, 1, 0),
    (3, 3004, 400, 1, 2, 1),
    (3, 3103, 300, 1, 1, 0),
    (3, 3104, 300, 1, 1, 0),
]


def build_stages() -> list[tuple]:
    """按章节生成关卡链，stage_id = 章节*1000 + 序号，pre_stage_id 串成引导线。"""
    rows, prev, seq = [], 0, 0
    total = sum(CONFIG_STAGE_COUNT.values())
    for chapter_id, _name, _order, _open in CONFIG_CHAPTERS:
        n = CONFIG_STAGE_COUNT[chapter_id]
        for i in range(1, n + 1):
            seq += 1
            stage_id = chapter_id * 1000 + i
            is_boss = i == n
            stage_type = 3 if is_boss else (2 if i % 4 == 0 else 1)
            group = 3 if is_boss else (2 if stage_type == 2 else 1)
            rows.append((
                stage_id, chapter_id, i, stage_type, group,
                6 if stage_type == 1 else (8 if stage_type == 2 else 10),
                30 * seq, 200 * seq, 1 if stage_type == 1 else (2 if stage_type == 2 else 3),
                json.dumps([{"item_id": 3002, "count": 20 * stage_type}], ensure_ascii=False),
                prev,
            ))
            prev = stage_id
    assert len(rows) == total, f"关卡数应为 {total}"
    return rows


# --------------------------------------------------------------------------- #
# 建库
# --------------------------------------------------------------------------- #
def remove_db(path: Path) -> None:
    """连 WAL / SHM 边车文件一起删干净。"""
    for suffix in ("", "-wal", "-shm"):
        f = Path(str(path) + suffix)
        if f.exists():
            f.unlink()


def build_cfg(force: bool) -> sqlite3.Connection:
    remove_db(CFG_DB)                       # 配置库每次都重建，权威来源是 schema.sql + 配置常量
    conn = sqlite3.connect(CFG_DB)
    sql = split_schema(SCHEMA_FILE)["cfg"]
    n = exec_script(conn, sql)
    conn.commit()
    print(f"[cfg] 建表 {n} 条语句 -> {CFG_DB.relative_to(ROOT)}")
    seed_cfg(conn)
    conn.commit()
    conn.execute("VACUUM")
    return conn


def seed_cfg(conn: sqlite3.Connection) -> None:
    conn.executemany(
        "INSERT INTO tb_cfg_hero (hero_id,name,quality,element,job,base_hp,base_atk,"
        "base_def,base_mres,base_spd,skill_ids,portrait,frame_asset) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
        [(h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8], h[9],
          json.dumps(h[10]), f"{ART}/characters/{h[11]}.png", FRAME[h[2]])
         for h in CONFIG_HEROES],
    )
    conn.executemany(
        "INSERT INTO tb_cfg_skill (skill_id,name,skill_type,target_type,power,cool_down,"
        "energy_cost,params,desc,icon) VALUES (?,?,?,?,?,?,?,'{}',?,'')",
        [(s[0], s[1], s[2], s[3], s[4], s[5], s[6], f"{s[1]}：技能占位描述") for s in CONFIG_SKILLS],
    )
    conn.executemany(
        "INSERT INTO tb_cfg_item (item_id,name,item_type,quality,max_stack,params,icon,desc) "
        "VALUES (?,?,?,?,?,?,?,?)",
        [(i[0], i[1], i[2], i[3], i[4], "{}", "", f"{i[1]}占位描述") for i in CONFIG_ITEMS],
    )
    conn.executemany(
        "INSERT INTO tb_cfg_chapter (chapter_id,name,order_no,open_level) VALUES (?,?,?,?)",
        CONFIG_CHAPTERS,
    )
    conn.executemany(
        "INSERT INTO tb_cfg_stage (stage_id,chapter_id,stage_no,stage_type,monster_group_id,"
        "stamina_cost,reward_exp,reward_gold,reward_group_id,first_clear,pre_stage_id) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?)",
        build_stages(),
    )
    conn.executemany(
        "INSERT INTO tb_cfg_monster_group (group_id,name,members) VALUES (?,?,?)",
        [(g[0], g[1], json.dumps(g[2], ensure_ascii=False)) for g in CONFIG_MONSTER_GROUPS],
    )
    conn.executemany(
        "INSERT INTO tb_cfg_drop_group (drop_group_id,item_id,weight,min_count,max_count,is_guaranteed) "
        "VALUES (?,?,?,?,?,?)",
        CONFIG_DROPS,
    )
    conn.execute(
        "INSERT INTO tb_cfg_gacha_pool (pool_id,name,cost_type,cost_single,pity_small,pity_big,"
        "up_hero_id,rates,open_from,open_to) VALUES (1,'常驻心愿池',2,1,50,100,1003,?,'','')",
        (json.dumps({"R": 70, "SR": 25, "SSR": 5}),),
    )
    counts = {
        t: conn.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        for t in ("tb_cfg_hero", "tb_cfg_skill", "tb_cfg_item", "tb_cfg_chapter",
                  "tb_cfg_stage", "tb_cfg_monster_group", "tb_cfg_drop_group", "tb_cfg_gacha_pool")
    }
    print("[cfg] 灌入配置 " + " ".join(f"{k.replace('tb_cfg_', '')}={v}" for k, v in counts.items()))


def build_player(force: bool, demo: bool) -> sqlite3.Connection:
    # 存档库默认不覆盖：里面可能有真实联调存档，必须显式 --force 才重建
    if PLAYER_DB.exists() and not force:
        conn = sqlite3.connect(PLAYER_DB)
        conn.execute("PRAGMA foreign_keys = ON")
        print(f"[player] 已存在，跳过重建 -> {PLAYER_DB.relative_to(ROOT)}（要重建请加 --force）")
        return conn
    remove_db(PLAYER_DB)
    conn = sqlite3.connect(PLAYER_DB)
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA foreign_keys = ON")
    n = exec_script(conn, split_schema(SCHEMA_FILE)["player"])
    conn.commit()
    print(f"[player] 建表 {n} 条语句 -> {PLAYER_DB.relative_to(ROOT)}")
    if demo:
        seed_demo(conn)
        conn.commit()
    conn.execute("VACUUM")                  # 整理页空间，让空档库保持最小体积
    return conn


def seed_demo(conn: sqlite3.Connection) -> None:
    cur = conn.execute(
        "INSERT INTO tb_player (account_id,nickname,avatar_id,level,exp,gold,diamond,"
        "pay_diamond,stamina,stamina_max) VALUES ('demo_local','无名散修',1001,5,1200,12000,300,0,108,120)"
    )
    pid = cur.lastrowid
    heroes = [(1001, 5, 2, 0), (1003, 5, 1, 0), (1004, 4, 1, 0)]
    guids = []
    for hero_id, level, star, bt in heroes:
        c = conn.execute(
            "INSERT INTO tb_player_hero (player_id,hero_id,level,star,break_through,equip_ids,skin_id) "
            "VALUES (?,?,?,?,?,'[]',0)", (pid, hero_id, level, star, bt))
        guids.append(c.lastrowid)
    conn.execute("UPDATE tb_player_hero SET equip_ids=? WHERE hero_guid=?",
                 (json.dumps([3103]), guids[1]))
    # 建号触发器已生成三类空阵型，这里写主线阵（UPSERT：无论是否存在都能落到同一状态）
    conn.execute(
        "INSERT INTO tb_player_formation (player_id,type,grid_data) VALUES (?,1,?) "
        "ON CONFLICT(player_id,type) DO UPDATE SET grid_data=excluded.grid_data",
        (pid, json.dumps({"pos_1": guids[0], "pos_2": guids[1], "pos_3": guids[2]})),
    )
    conn.executemany("INSERT INTO tb_player_item (player_id,item_id,\"count\") VALUES (?,?,?)",
                     [(pid, 3002, 150), (pid, 3001, 30), (pid, 3003, 6), (pid, 3103, 1)])
    conn.execute(
        "UPDATE tb_player_stage SET max_stage_id=1003, stage_stars=? WHERE player_id=?",
        (json.dumps({"1001": 3, "1002": 3, "1003": 2}), pid),
    )
    conn.execute("INSERT INTO tb_player_gacha (player_id,pool_id,pity_count,big_pity_count,total_draws) "
                 "VALUES (?,1,12,12,38)", (pid,))
    print(f"[player] 演示存档已写入 player_id={pid}（仅限联调，勿随包发布）")


# --------------------------------------------------------------------------- #
# 自检
# --------------------------------------------------------------------------- #
def verify(cfg: sqlite3.Connection, player: sqlite3.Connection) -> None:
    print("\n===== 自检 =====")
    print("[cfg] integrity_check :", cfg.execute("PRAGMA integrity_check").fetchone()[0])
    print("[player] integrity_check:", player.execute("PRAGMA integrity_check").fetchone()[0])
    print("[player] foreign_key_check:", player.execute("PRAGMA foreign_key_check").fetchall() or "OK")

    bad = player.execute(
        "SELECT COUNT(*) FROM tb_player_hero WHERE NOT json_valid(equip_ids)").fetchone()[0]
    print("[player] equip_ids JSON 非法行数:", bad)

    # 触发器：updated_at 自动刷新
    row = player.execute("SELECT player_id,updated_at FROM tb_player LIMIT 1").fetchone()
    if row:
        pid, before = row
        player.execute("UPDATE tb_player SET updated_at='2000-01-01 00:00:00' WHERE player_id=?", (pid,))
        player.execute("UPDATE tb_player SET level=level+1 WHERE player_id=?", (pid,))
        after = player.execute("SELECT updated_at FROM tb_player WHERE player_id=?", (pid,)).fetchone()[0]
        print(f"[player] updated_at 触发器: 2000-01-01 -> {after}  {'OK' if after != '2000-01-01 00:00:00' else 'FAIL'}")
        player.execute("UPDATE tb_player SET level=level-1 WHERE player_id=?", (pid,))

    # 触发器：建号自动补 tb_player_stage + 三条空阵型
    c = player.execute("INSERT INTO tb_player (account_id,nickname) VALUES ('__tmp_probe__','探针')")
    probe = c.lastrowid
    got = player.execute("SELECT COUNT(*) FROM tb_player_stage WHERE player_id=?", (probe,)).fetchone()[0]
    print(f"[player] 建号自动补关卡进度: {'OK' if got == 1 else 'FAIL'}")
    fgot = player.execute("SELECT COUNT(*) FROM tb_player_formation WHERE player_id=?", (probe,)).fetchone()[0]
    print(f"[player] 建号自动补三类阵型: {'OK' if fgot == 3 else f'FAIL (got {fgot})'}")

    # 级联删除
    player.execute("INSERT INTO tb_player_item (player_id,item_id,\"count\") VALUES (?,3002,5)", (probe,))
    player.execute("DELETE FROM tb_player WHERE player_id=?", (probe,))
    left = player.execute("SELECT COUNT(*) FROM tb_player_item WHERE player_id=?", (probe,)).fetchone()[0]
    print(f"[player] ON DELETE CASCADE 清理孤行: {'OK' if left == 0 else 'FAIL'}")
    player.rollback()

    # 演示存档快照（通过视图）
    rows = player.execute(
        "SELECT nickname,hero_id,level,star,equip_count FROM v_player_hero_brief ORDER BY hero_guid"
    ).fetchall()
    if rows:
        print("[player] v_player_hero_brief:")
        for r in rows:
            print(f"          {r[0]} | hero_id={r[1]} lv{r[2]} ★{r[3]} 装备{r[4]}件")
    print("[cfg] 关卡链样例:",
          cfg.execute("SELECT stage_id,stage_type,pre_stage_id,stamina_cost FROM tb_cfg_stage "
                      "ORDER BY stage_id LIMIT 5").fetchall(), "...")


def main() -> None:
    ap = argparse.ArgumentParser(description="构建 SQLite 配置库与玩家存档库")
    ap.add_argument("--force", action="store_true", help="覆盖已存在的 db 文件")
    ap.add_argument("--demo", action="store_true", help="向存档库写入演示玩家数据")
    ap.add_argument("--verify", action="store_true", help="构建后运行自检")
    args = ap.parse_args()

    DB_DIR.mkdir(parents=True, exist_ok=True)
    cfg = build_cfg(args.force)
    player = build_player(args.force, args.demo)
    if args.verify:
        verify(cfg, player)
    for f in (CFG_DB, PLAYER_DB):
        print(f"  -> {f.relative_to(ROOT)}  {f.stat().st_size / 1024:.1f} KB")
    cfg.close()
    player.close()
    print("\n完成。Godot 侧加载示例：")
    print('  var db := SQLite.new()')
    print('  db.path = "res://data/db/game_cfg.db"; db.read_only = true; db.open_db()')
    print('  db.path = "user://player_save.db";          db.open_db()   # 存档放 user:// 可写目录')


if __name__ == "__main__":
    main()
