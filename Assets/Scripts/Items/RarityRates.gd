class_name RarityRates
extends Resource

@export var rest_area_visit: int = 1
@export var common_rate: float = 0.80
@export var rare_rate: float = 0.15
@export var epic_rate: float = 0.05

func roll_rarity() -> ItemRarity:
	var roll = randf()
	if roll < epic_rate:
		return load("res://Resources/SizeTiers/epic.tres")
	elif roll < epic_rate + rare_rate:
		return load("res://Resources/SizeTiers/rare.tres")
	else:
		return load("res://Resources/SizeTiers/common.tres")
