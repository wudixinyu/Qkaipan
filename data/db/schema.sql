-- =============================================================================
--  《项目代号：卡牌大冒险》SQLite 数据库 Schema
--  由 MySQL/PostgreSQL 版设计文档转换而来（SQLite 3.38+ / JSON1 内置）
--  单一源文件，构建时按 `-- @db:` 标记切分成两个物理库：
--    @db: cfg     -> data/db/game_cfg.db     静态配置（随包发布、只读、可热更）
--    @db: player  -> data/db/player_save.db  玩家存档（可写、WAL、需备份）
--  构建脚本：tools/init_game_db.py
--  ---------------------------------------------------------------------------
--  【为什么拆成两个文件而不是两套表】
--    SQLite 的文件即"库"。把配置与存档物理隔离后可以做到：
--    ① 配置热更新只替换 game_cfg.db，完全不动玩家存档；
--    ② 存档库体积小、备份/回滚成本低；
--    ③ 配置库以只读方式打开，避免运行时被误写。
--    代价：跨文件无法建立 FOREIGN KEY，hero_id / item_id / stage_id 这类
--    "指向配置表"的列不做数据库级外键约束，完整性由应用层（GameDB 层）
--    校验。若要临时联表，用 ATTACH DATABASE 挂载后再 JOIN。
--  ---------------------------------------------------------------------------
--  【MySQL -> SQLite 类型与语法映射】
--    BIGINT / INT / TINYINT / SMALLINT   -> INTEGER
--    VARCHAR(n) / CHAR(n)                -> TEXT        （SQLite 不强制长度）
--    JSON                                -> TEXT + CHECK(json_valid(x))
--    TIMESTAMP / DATETIME                -> TEXT（ISO8601 字符串）
--    BOOLEAN                             -> INTEGER (0/1)
--    ENUM(...)                           -> TEXT/INTEGER + CHECK (x IN (...))
--    DECIMAL(p,s)                        -> INTEGER 存分值，或 REAL/TEXT
--    BLOB                                -> BLOB（原样保留）
--    AUTO_INCREMENT                      -> INTEGER PRIMARY KEY AUTOINCREMENT
--    ENGINE=InnoDB DEFAULT CHARSET=utf8mb4  -> 删除（SQLite 无需指定）
--    COMMENT '...'                       -> SQL 行注释 `-- ...`
--    ON UPDATE CURRENT_TIMESTAMP         -> 触发器 trg_*_updated（见文末）
--    INDEX / KEY                         -> 独立 CREATE INDEX 语句
--  ---------------------------------------------------------------------------
--  【时间口径】
--    MySQL 的 CURRENT_TIMESTAMP 为服务器本地时区；SQLite 的 CURRENT_TIMESTAMP
--    恒为 UTC。本项目统一使用 datetime('now','localtime')，存本地时间字符串，
--    与策划配置、玩家感知一致。时间比较可直接用字符串比较（ISO8601 可排序）。
--    体力恢复、挂机收益这类"时间差计算"建议改存 Unix 时间戳（INTEGER），
--    已在标注处给出替代写法。
-- =============================================================================

-- =============================================================================
-- @db: cfg
-- 静态配置库（Game Configuration DB）
-- =============================================================================

PRAGMA encoding = 'UTF-8';
PRAGMA user_version = 1;          -- 配置表结构版本，供热更时做迁移判断

-- -----------------------------------------------------------------------------
-- 2.1 英雄基础配置表
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tb_cfg_hero (
  hero_id     INTEGER PRIMARY KEY,                                    -- 卡牌ID
  name        TEXT    NOT NULL DEFAULT '',                            -- 英雄名称
  quality     INTEGER NOT NULL CHECK (quality BETWEEN 1 AND 4),        -- 品质: 1-R 2-SR 3-SSR 4-UR
  element     INTEGER NOT NULL CHECK (element BETWEEN 1 AND 6),        -- 属性: 1-水 2-火 3-风 4-地 5-光 6-暗
  job         INTEGER NOT NULL CHECK (job     BETWEEN 1 AND 4),        -- 职业: 1-前排 2-输出 3-辅助 4-刺客
  base_hp     INTEGER NOT NULL DEFAULT 0,                             -- 基础生命
  base_atk    INTEGER NOT NULL DEFAULT 0,                             -- 基础攻击
  base_def    INTEGER NOT NULL DEFAULT 0,                             -- 基础物理防御
  base_mres   INTEGER NOT NULL DEFAULT 0,                             -- 基础魔法抗性
  base_spd    INTEGER NOT NULL DEFAULT 0,                             -- 基础攻速
  skill_ids   TEXT    NOT NULL DEFAULT '[]' CHECK (json_valid(skill_ids)),  -- 技能列表 [1,2,3]
  portrait    TEXT    NOT NULL DEFAULT '',                            -- 立绘资源路径（新增，对接 assets/art/characters）
  frame_asset TEXT    NOT NULL DEFAULT ''                             -- 卡框资源名 r/sr/ssr/ur（新增，对接 assets/art/frames）
);

-- -----------------------------------------------------------------------------
-- 2.x 技能配置表（原文档仅被引用，此处补全为可落库定义）
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tb_cfg_skill (
  skill_id      INTEGER PRIMARY KEY,                                  -- 技能ID
  name          TEXT    NOT NULL DEFAULT '',
  skill_type    INTEGER NOT NULL DEFAULT 1,                           -- 1-主动 2-被动 3-追击
  target_type   INTEGER NOT NULL DEFAULT 1,                           -- 1-单体敌方 2-全体敌方 3-己方单体 4-己方全体 5-自身
  power         INTEGER NOT NULL DEFAULT 0,                           -- 伤害/治疗系数（万分比）
  cool_down     INTEGER NOT NULL DEFAULT 0,                           -- 冷却回合数
  energy_cost   INTEGER NOT NULL DEFAULT 0,                           -- 怒气/灵力消耗
  params        TEXT    NOT NULL DEFAULT '{}' CHECK (json_valid(params)),  -- 扩展参数
  desc          TEXT    NOT NULL DEFAULT '',
  icon          TEXT    NOT NULL DEFAULT ''
);

-- -----------------------------------------------------------------------------
-- 2.x 道具配置表（原文档 tb_player_item.item_id 指向此表）
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tb_cfg_item (
  item_id     INTEGER PRIMARY KEY,                                    -- 道具ID
  name        TEXT    NOT NULL DEFAULT '',
  item_type   INTEGER NOT NULL DEFAULT 1,                             -- 1-装备 2-材料 3-消耗品 4-卡牌碎片 5-礼包
  quality     INTEGER NOT NULL DEFAULT 1 CHECK (quality BETWEEN 1 AND 4),
  max_stack   INTEGER NOT NULL DEFAULT 9999,                          -- 堆叠上限（1 = 不可堆叠）
  params      TEXT    NOT NULL DEFAULT '{}' CHECK (json_valid(params)),  -- 装备属性/使用效果
  icon        TEXT    NOT NULL DEFAULT '',
  desc        TEXT    NOT NULL DEFAULT ''
);

-- -----------------------------------------------------------------------------
-- 2.x 章节配置表
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tb_cfg_chapter (
  chapter_id   INTEGER PRIMARY KEY,
  name         TEXT    NOT NULL DEFAULT '',
  order_no     INTEGER NOT NULL DEFAULT 0,                            -- 章节顺序
  open_level   INTEGER NOT NULL DEFAULT 1                             -- 解锁所需玩家等级
);

-- -----------------------------------------------------------------------------
-- 2.2 关卡配置表
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tb_cfg_stage (
  stage_id         INTEGER PRIMARY KEY,                               -- 关卡ID
  chapter_id       INTEGER NOT NULL,                                  -- 所属章节
  stage_no         INTEGER NOT NULL DEFAULT 0,                        -- 章内序号（新增，用于排序/引导线）
  stage_type       INTEGER NOT NULL DEFAULT 1 CHECK (stage_type BETWEEN 1 AND 3), -- 1-普通 2-精英 3-BOSS
  monster_group_id INTEGER NOT NULL,                                  -- 对应怪物阵型组ID
  stamina_cost     INTEGER NOT NULL DEFAULT 6,                        -- 消耗体力
  reward_exp       INTEGER NOT NULL DEFAULT 0,                        -- 掉落经验
  reward_gold      INTEGER NOT NULL DEFAULT 0,                        -- 掉落金币
  reward_group_id  INTEGER NOT NULL DEFAULT 0,                        -- 掉落概率组ID（原 drop_group_id）
  first_clear      TEXT    NOT NULL DEFAULT '[]' CHECK (json_valid(first_clear)), -- 首通奖励
  pre_stage_id     INTEGER NOT NULL DEFAULT 0                         -- 前置关卡（0=无），用于关卡引导线
);

-- -----------------------------------------------------------------------------
-- 2.x 怪物阵型组配置表
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tb_cfg_monster_group (
  group_id     INTEGER PRIMARY KEY,                                   -- 怪物组ID
  name         TEXT    NOT NULL DEFAULT '',
  members      TEXT    NOT NULL DEFAULT '[]' CHECK (json_valid(members))  -- [{hero_id,level,star,pos}]
);

-- -----------------------------------------------------------------------------
-- 2.x 掉落组配置表（一条掉落项一行，按 weight 权重随机）
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tb_cfg_drop_group (
  drop_id        INTEGER PRIMARY KEY AUTOINCREMENT,
  drop_group_id  INTEGER NOT NULL,                                    -- 掉落组ID
  item_id        INTEGER NOT NULL,
  weight         INTEGER NOT NULL DEFAULT 1000,                       -- 权重（千分比）
  min_count      INTEGER NOT NULL DEFAULT 1,
  max_count      INTEGER NOT NULL DEFAULT 1,
  is_guaranteed  INTEGER NOT NULL DEFAULT 0 CHECK (is_guaranteed IN (0,1))  -- 1=必掉
);

-- -----------------------------------------------------------------------------
-- 2.x 抽卡池配置表（tb_player_gacha.pool_id 指向此表）
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tb_cfg_gacha_pool (
  pool_id      INTEGER PRIMARY KEY,
  name         TEXT    NOT NULL DEFAULT '',
  cost_type    INTEGER NOT NULL DEFAULT 1,                            -- 1-钻石券 2-彩虹钻石 3-金币
  cost_single  INTEGER NOT NULL DEFAULT 1,                            -- 单抽消耗
  pity_small   INTEGER NOT NULL DEFAULT 50,                           -- 小保底（必出SSR）
  pity_big     INTEGER NOT NULL DEFAULT 100,                          -- 大保底（必出UP）
  up_hero_id   INTEGER NOT NULL DEFAULT 0,                            -- 当期UP卡牌ID
  rates        TEXT    NOT NULL DEFAULT '{}' CHECK (json_valid(rates)),  -- {"R":0.7,"SR":0.25,"SSR":0.05}
  open_from    TEXT    NOT NULL DEFAULT '',
  open_to      TEXT    NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_cfg_stage_chapter ON tb_cfg_stage(chapter_id, stage_no);
CREATE INDEX IF NOT EXISTS idx_cfg_drop_group    ON tb_cfg_drop_group(drop_group_id);

-- =============================================================================
-- @db: player
-- 动态玩家库（Player Data DB）
-- =============================================================================

PRAGMA encoding = 'UTF-8';
PRAGMA foreign_keys = ON;         -- 存档库内部父子表启用外键级联
PRAGMA user_version = 1;          -- 存档结构版本，用于版本升级迁移

-- -----------------------------------------------------------------------------
-- 1.1 玩家基础信息表
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tb_player (
  player_id         INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id        TEXT    NOT NULL UNIQUE,                          -- 平台账号ID / OpenID
  nickname          TEXT    NOT NULL DEFAULT '',
  avatar_id         INTEGER NOT NULL DEFAULT 1001,
  level             INTEGER NOT NULL DEFAULT 1 CHECK (level >= 1),
  exp               INTEGER NOT NULL DEFAULT 0 CHECK (exp >= 0),
  gold              INTEGER NOT NULL DEFAULT 0 CHECK (gold >= 0),      -- 软代币：金币
  diamond           INTEGER NOT NULL DEFAULT 0 CHECK (diamond >= 0),   -- 绑定钻石
  pay_diamond       INTEGER NOT NULL DEFAULT 0 CHECK (pay_diamond >= 0), -- 硬代币：彩虹钻石
  stamina           INTEGER NOT NULL DEFAULT 120 CHECK (stamina >= 0), -- 当前体力值
  stamina_max       INTEGER NOT NULL DEFAULT 120,                      -- 体力上限（新增，恢复计算需要）
  last_stamina_time TEXT    NOT NULL DEFAULT (datetime('now','localtime')), -- 上次结算体力时间
  created_at        TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
  updated_at        TEXT    NOT NULL DEFAULT (datetime('now','localtime'))
);

-- -----------------------------------------------------------------------------
-- 1.2 玩家卡牌表（一行 = 一张具体卡牌实例）
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tb_player_hero (
  hero_guid     INTEGER PRIMARY KEY AUTOINCREMENT,                    -- 卡牌唯一实例ID
  player_id     INTEGER NOT NULL REFERENCES tb_player(player_id) ON DELETE CASCADE,
  hero_id       INTEGER NOT NULL,                                     -- 静态卡牌ID -> tb_cfg_hero.hero_id（跨库，应用层校验）
  level         INTEGER NOT NULL DEFAULT 1 CHECK (level >= 1),
  star          INTEGER NOT NULL DEFAULT 1 CHECK (star BETWEEN 1 AND 6),
  break_through INTEGER NOT NULL DEFAULT 0 CHECK (break_through >= 0),
  equip_ids     TEXT    NOT NULL DEFAULT '[]' CHECK (json_valid(equip_ids)),  -- 装备实例ID集合 [eq_guid1,...]
  skin_id       INTEGER NOT NULL DEFAULT 0,
  obtained_at   TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
  UNIQUE (player_id, hero_guid)                                       -- 防跨玩家串号
);

-- -----------------------------------------------------------------------------
-- 1.3 玩家阵型表
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tb_player_formation (
  formation_id INTEGER PRIMARY KEY AUTOINCREMENT,
  player_id    INTEGER NOT NULL REFERENCES tb_player(player_id) ON DELETE CASCADE,
  type         INTEGER NOT NULL CHECK (type BETWEEN 1 AND 3),          -- 1-主线冒险 2-竞技场防守 3-无尽之塔
  grid_data    TEXT    NOT NULL DEFAULT '{}' CHECK (json_valid(grid_data)), -- {"pos_1": hero_guid, "pos_5": hero_guid}
  updated_at   TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
  UNIQUE (player_id, type)                                            -- 每类阵型每人仅一条
);

-- -----------------------------------------------------------------------------
-- 1.4 玩家背包 / 物品表
-- -----------------------------------------------------------------------------
-- 注意：`count` 是 SQLite 内置函数名，此处保留文档原字段名但必须用双引号引用；
--      若嫌麻烦可全局改名为 item_count（代码里同步改即可）。
CREATE TABLE IF NOT EXISTS tb_player_item (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  player_id INTEGER NOT NULL REFERENCES tb_player(player_id) ON DELETE CASCADE,
  item_id   INTEGER NOT NULL,                                         -- 静态道具ID -> tb_cfg_item.item_id
  "count"   INTEGER NOT NULL DEFAULT 0 CHECK ("count" >= 0),
  UNIQUE (player_id, item_id)                                         -- 堆叠：同玩家同道具仅一行
);

-- -----------------------------------------------------------------------------
-- 1.5 玩家主线 / 关卡进度表（一人一行）
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tb_player_stage (
  player_id      INTEGER PRIMARY KEY REFERENCES tb_player(player_id) ON DELETE CASCADE,
  max_stage_id   INTEGER NOT NULL DEFAULT 1001,                        -- 当前最高通关关卡ID
  stage_stars    TEXT    NOT NULL DEFAULT '{}' CHECK (json_valid(stage_stars)), -- {"1001":3,"1002":2}
  afk_start_time TEXT    NOT NULL DEFAULT (datetime('now','localtime')), -- 挂机收益起算时间
  afk_claimed_at TEXT    NOT NULL DEFAULT ''                           -- 上次领取挂机收益时间（新增）
);

-- -----------------------------------------------------------------------------
-- 1.6 玩家抽卡 / 保底数据表（复合主键，无需自增ID）
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tb_player_gacha (
  player_id      INTEGER NOT NULL REFERENCES tb_player(player_id) ON DELETE CASCADE,
  pool_id        INTEGER NOT NULL,                                     -- 抽卡池ID -> tb_cfg_gacha_pool.pool_id
  pity_count     INTEGER NOT NULL DEFAULT 0 CHECK (pity_count >= 0),    -- 小保底已抽次数（50 抽必出 SSR）
  big_pity_count INTEGER NOT NULL DEFAULT 0 CHECK (big_pity_count >= 0),-- 大保底已抽次数（100 抽必出 UP）
  total_draws    INTEGER NOT NULL DEFAULT 0 CHECK (total_draws >= 0),   -- 该池累计抽卡次数
  updated_at     TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
  PRIMARY KEY (player_id, pool_id)
) WITHOUT ROWID;                                                       -- 纯关联表，省一层 rowid 索引

-- -----------------------------------------------------------------------------
-- 存档库索引
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_player_hero_owner  ON tb_player_hero(player_id, hero_id);
CREATE INDEX IF NOT EXISTS idx_player_item_owner  ON tb_player_item(player_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_player_account ON tb_player(account_id);

-- -----------------------------------------------------------------------------
-- updated_at 自动维护（替代 MySQL 的 ON UPDATE CURRENT_TIMESTAMP）
-- 递归触发器默认关闭，配合 WHEN 守卫不会自激。
-- -----------------------------------------------------------------------------
CREATE TRIGGER IF NOT EXISTS trg_player_updated
AFTER UPDATE ON tb_player
FOR EACH ROW WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE tb_player SET updated_at = datetime('now','localtime')
   WHERE player_id = NEW.player_id;
END;

CREATE TRIGGER IF NOT EXISTS trg_formation_updated
AFTER UPDATE ON tb_player_formation
FOR EACH ROW WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE tb_player_formation SET updated_at = datetime('now','localtime')
   WHERE formation_id = NEW.formation_id;
END;

CREATE TRIGGER IF NOT EXISTS trg_gacha_updated
AFTER UPDATE ON tb_player_gacha
FOR EACH ROW WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE tb_player_gacha SET updated_at = datetime('now','localtime')
   WHERE player_id = NEW.player_id AND pool_id = NEW.pool_id;
END;

-- -----------------------------------------------------------------------------
-- 新号初始化触发器：插入 tb_player 时自动补
--   ① tb_player_stage   一行主线进度
--   ② tb_player_formation 三个玩法各一行的空阵型（type 1/2/3）
-- （MySQL 侧通常由服务端建号逻辑完成，SQLite 里用触发器兜底，避免应用层漏写）
-- -----------------------------------------------------------------------------
CREATE TRIGGER IF NOT EXISTS trg_player_after_insert
AFTER INSERT ON tb_player
FOR EACH ROW
BEGIN
  INSERT INTO tb_player_stage (player_id, max_stage_id, stage_stars, afk_start_time, afk_claimed_at)
  VALUES (NEW.player_id, 1001, '{}', datetime('now','localtime'), datetime('now','localtime'));

  INSERT INTO tb_player_formation (player_id, type, grid_data) VALUES (NEW.player_id, 1, '{}');
  INSERT INTO tb_player_formation (player_id, type, grid_data) VALUES (NEW.player_id, 2, '{}');
  INSERT INTO tb_player_formation (player_id, type, grid_data) VALUES (NEW.player_id, 3, '{}');
END;

-- -----------------------------------------------------------------------------
-- 存档库便捷视图：卡牌实例 + 归属校验（配置字段需 ATTACH 后另行 JOIN）
-- -----------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS v_player_hero_brief AS
SELECT h.player_id,
       h.hero_guid,
       h.hero_id,
       h.level,
       h.star,
       h.break_through,
       json_array_length(h.equip_ids) AS equip_count,
       p.nickname
  FROM tb_player_hero h
  JOIN tb_player p ON p.player_id = h.player_id;
