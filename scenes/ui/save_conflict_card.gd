class_name SaveConflictCard
extends Control
## Asks the player which save is theirs, when the game genuinely cannot tell.
##
## This is the only screen in the game whose wrong answer costs progress, so it is built to be
## read rather than dismissed: no default button, no timeout, no way to close it without choosing.
## A card that could be escaped would need a behaviour for "escaped", and every candidate for that
## behaviour is a guess of exactly the kind the whole sync path refuses to make.
##
## The two sides are described in the only terms a player can check against their own memory —
## runs played, bosses beaten, whether there is a run to continue and how far in. Hashes and
## timestamps would be more precise and less useful: nobody knows which of two SHA-256s is theirs.

signal chosen(resolution: CloudSaveCoordinator.Resolution)

@onready var _local_summary: Label = %LocalSummary
@onready var _cloud_summary: Label = %CloudSummary
@onready var _keep_local: Button = %KeepLocal
@onready var _take_cloud: Button = %TakeCloud


func _ready() -> void:
	_keep_local.pressed.connect(_on_chosen.bind(CloudSaveCoordinator.Resolution.KEEP_LOCAL))
	_take_cloud.pressed.connect(_on_chosen.bind(CloudSaveCoordinator.Resolution.TAKE_CLOUD))


## Fills the card in and takes focus. Called after the card is in the tree, so the labels exist.
func present(local: Dictionary, cloud: Dictionary) -> void:
	_local_summary.text = _describe(local)
	_cloud_summary.text = _describe(cloud)
	# Focus goes to the local copy because it is the one on the machine in front of them, not
	# because it is the recommended answer. There is no recommended answer.
	_keep_local.grab_focus()


func _describe(summary: Dictionary) -> String:
	if summary.is_empty():
		return "No details available"

	var lines := PackedStringArray()
	lines.append("%d runs started" % int(summary.get("runs_started", 0)))
	lines.append("%d bosses beaten" % int(summary.get("bosses_defeated", 0)))
	if summary.get("has_checkpoint", false):
		lines.append("Run in progress on floor %d" % int(summary.get("checkpoint_floor", 0)))
	else:
		lines.append("No run in progress")
	return "\n".join(lines)


func _on_chosen(resolution: CloudSaveCoordinator.Resolution) -> void:
	# Both buttons go dead the instant either is pressed. The choice is acted on across an await,
	# and a second press during it would answer a question that has already been answered.
	_keep_local.disabled = true
	_take_cloud.disabled = true
	chosen.emit(resolution)
