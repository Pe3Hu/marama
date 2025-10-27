class_name Token
extends PanelContainer


@export var value: int:
	set(value_):
		value = value_
		
		%ValueLabel.text = str(value)
@export_enum("action", "block", "member", "reactor", "thruster", "damage", "shield", "miss", "hazard") var type: String = "miss":
	set(value_):
		type = value_
		
		%TextureRect.texture = load("res://entities/bank/token/images/" + type + ".png")
		
		match type:
			"reactor":
				%ColorRect.color = Color.ROYAL_BLUE
			"action":
				%ColorRect.color = Color.DODGER_BLUE
			"thruster":
				%ColorRect.color = Color.GOLD
			"damage":
				%ColorRect.color = Color.TOMATO
			"shield":
				%ColorRect.color = Color.LIME_GREEN
			"block":
				%ColorRect.color = Color.LIME_GREEN
			"hazard":
				%ColorRect.color = Color.DARK_RED
			"member":
				%ColorRect.color = Color.REBECCA_PURPLE
			"miss":
				%ColorRect.color = Color.WEB_GRAY
