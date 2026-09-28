extends Node
## StaminaSys —— 体力系统（1 点 / 5 分钟，离线累计）
##
## 唯一职责：维护体力值与恢复计时。恢复以「上次结算时刻 + 经过秒数」推算，
## 因此关掉游戏再回来也能正确补足，不依赖后台常驻。
##
## 结算语义：只增不减。恢复只做加法，扣减只由 spend() 显式触发。

signal changed(current: int, maximum: int)
signal recovered(amount: int)

const TICK_INTERVAL := 1.0

var _value: int = 0
var _accounted_at: int = 0
var _accum: float = 0.0


func _ready() -> void:
	var st: Dictionary = SaveDB.profile.get("stamina", {})
	_value = int(st.get("value", maximum()))
	_accounted_at = int(st.get("accounted_at", 0))
	if _accounted_at <= 0:
		_value = maximum()
		_accounted_at = now()
		_persist()
	else:
		apply_offline()
	_bind()

	var t := Timer.new()
	t.wait_time = TICK_INTERVAL
	t.autostart = true
	t.timeout.connect(_on_tick)
	add_child(t)
	changed.emit(_value, maximum())


func _bind() -> void:
	# 存档被重置时同步重置体力
	SaveDB.loaded.connect(_reload_from_save)


func _reload_from_save() -> void:
	var st: Dictionary = SaveDB.profile.get("stamina", {})
	_value = int(st.get("value", maximum()))
	_accounted_at = int(st.get("accounted_at", now()))
	apply_offline()
	changed.emit(_value, maximum())


# ---------------------------------------------------------------- 查询

func maximum() -> int:
	return int(GameDB.stamina_cfg().get("max", 60))


func seconds_per_point() -> int:
	return int(GameDB.stamina_cfg().get("seconds_per_point", 300))


func current() -> int:
	return _value


func is_full() -> bool:
	return _value >= maximum()


## 距离下一点恢复还有多少秒；满体力返回 0
func seconds_to_next() -> int:
	if is_full():
		return 0
	var per := seconds_per_point()
	var elapsed := float(now() - _accounted_at) + _accum
	var into := int(elapsed) % per
	return max(0, per - into)


func regen_per_hour() -> int:
	return int(3600 / max(1, seconds_per_point()))


# ---------------------------------------------------------------- 变更

func spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if _value < amount:
		return false
	_value -= amount
	# 从满值变非满时才需要开始计时，避免离线期间把恢复时间吃掉
	if _accounted_at <= 0:
		_accounted_at = now()
	_persist()
	changed.emit(_value, maximum())
	return true


func grant(amount: int) -> void:
	if amount <= 0:
		return
	_value = min(maximum(), _value + amount)
	if is_full():
		_accounted_at = now()
		_accum = 0.0
	_persist()
	changed.emit(_value, maximum())


func fill() -> void:
	_value = maximum()
	_accounted_at = now()
	_accum = 0.0
	_persist()
	changed.emit(_value, maximum())


## 结算离线 / 空闲期间的恢复
func apply_offline() -> int:
	if is_full():
		_accounted_at = now()
		_accum = 0.0
		return 0
	var per := seconds_per_point()
	var elapsed := float(now() - _accounted_at) + _accum
	var gained := int(elapsed / float(per))
	if gained <= 0:
		return 0
	var before := _value
	_value = min(maximum(), _value + gained)
	_accum = elapsed - float(gained) * float(per)
	_accounted_at = now()
	if is_full():
		_accum = 0.0
	_persist()
	var real := _value - before
	if real > 0:
		recovered.emit(real)
		changed.emit(_value, maximum())
	return real


func _persist() -> void:
	SaveDB.profile["stamina"] = { "value": _value, "accounted_at": _accounted_at }
	SaveDB.save_profile()


# ---------------------------------------------------------------- 内部

func now() -> int:
	return int(Time.get_unix_time_from_system())


func _on_tick() -> void:
	_accum += TICK_INTERVAL
	if is_full():
		_accum = 0.0
		return
	if _accum >= float(seconds_per_point()) or regen_per_hour() >= 3600:
		apply_offline()
	else:
		# 低频落盘：每 30 秒更新一次记账时刻，避免频繁写盘
		if int(_accum) % 30 == 0:
			_persist()


func format_next() -> String:
	if is_full():
		return "已满"
	var s := seconds_to_next()
	return "%02d:%02d" % [s / 60, s % 60]
