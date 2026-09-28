extends Node
## BattleCtx —— 一场战斗的上下文（选关页 → 战斗场景之间唯一的交接面）
##
## 为什么不塞进 SaveDB：这些是**单场临时状态**（本场是哪一关、有没有带祭坛祝福），
## 落盘既没意义又会污染存档；也不该挂在 stage_select 的节点上 —— 换场景后节点就没了。
## 于是单独做一个最薄的 autoload，只存「这一趟去打架要带什么」。

signal begun(stage_id: int)

var stage_id: int = 0
var source: String = ""            ## 从哪进来的（stage_select / retry / debug），只用于提示
var atk_bonus: float = 1.0         ## 祭坛「祈祷」之类的下一场增益
var buff_name: String = ""
var buff_desc: String = ""
## 固定随机种子：-1 = 每场随机。冒烟测试与截图自检会把它设成一个定值，
## 这样「同一关跑出来的过程和结果」可复现，截图和断言才有意义。
var seed_override: int = -1


func begin_from_stage(p_stage_id: int, from: String = "stage_select") -> void:
	stage_id = p_stage_id
	source = from
	# 增益只生效一场：开局即消费（祝福本身已经在祭坛那边结算过）
	begun.emit(stage_id)


func begin_with_buff(p_stage_id: int, mult: float, name_text: String, desc: String) -> void:
	begin_from_stage(p_stage_id, "altar")
	atk_bonus = maxf(1.0, mult)
	buff_name = name_text
	buff_desc = desc


## 战斗结束后清掉临时增益，避免带到下一场
func consume_buff() -> void:
	atk_bonus = 1.0
	buff_name = ""
	buff_desc = ""


func reset() -> void:
	stage_id = 0
	source = ""
	seed_override = -1
	consume_buff()


func describe() -> String:
	if atk_bonus <= 1.0:
		return "本场无额外增益"
	return "【%s】%s（%s）" % [buff_name, buff_desc, "本场生效"]
