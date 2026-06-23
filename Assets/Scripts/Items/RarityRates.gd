class_name RarityRates
extends Resource

@export var rest_area_visit: int = 1
@export var small_rate: float = 0.75
@export var medium_rate: float = 0.20
@export var large_rate: float = 0.05

func roll_rarity() -> ItemRarity:
	var roll = randf()
	if roll < large_rate:
		return load("res://Resources/SizeTiers/large.tres")
	elif roll < large_rate + medium_rate:
		return load("res://Resources/SizeTiers/medium.tres")
	else:
		return load("res://Resources/SizeTiers/small.tres")
