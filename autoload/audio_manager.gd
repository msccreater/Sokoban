extends Node

var sfx_enabled: bool = true

# 音效资源路径
const SFX = {
	"click": "res://assets/audio/click.mp3",
	"move": "res://assets/audio/move.mp3",
	"push": "res://assets/audio/push.mp3",
	"restart": "res://assets/audio/restart.mp3",
	"result": "res://assets/audio/result.mp3",
	"rollbackmove": "res://assets/audio/rollbackmove.mp3",
	"rollbackpush": "res://assets/audio/rollbackpush.mp3",
}

func _ready() -> void:
	sfx_enabled = SaveManager.get_bool("SFX_enable", true)

func set_sfx(enable: bool) -> void:
	if sfx_enabled == enable:
		return
	sfx_enabled = enable
	SaveManager.set_bool("SFX_enable", enable)

func get_sfx() -> bool:
	return sfx_enabled

func play_sfx(sfx_name: String, volume: float = 1.0):
	if not sfx_enabled:
		return
	var path = SFX.get(sfx_name)
	if not path:
		return
	var player = AudioStreamPlayer.new()
	player.bus = "SFX"
	player.stream = load(path)
	player.volume_db = linear_to_db(volume)
	player.finished.connect(player.queue_free)  # 播放完毕自动释放
	add_child(player)
	player.play()
