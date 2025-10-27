class_name Bank
extends PanelContainer


##
@export var tablet: Tablet

##
@onready var contracts = %Contracts
@onready var tokens = %Tokens
@onready var reactor_token = %ReactorToken
@onready var thruster_token = %ThrusterToken
@onready var damage_token = %DamageToken
@onready var shield_token = %ShieldToken
@onready var hazard_token = %HazardToken
@onready var action_token = %ActionToken

var is_locked: bool = true


func reset_tokens() -> void:
	for contract_token in contracts.get_children():
		contract_token.value = 0
		
	for temp_token in tokens.get_children():
		temp_token.value = 0
	
	action_token.value = 1
	
func apply_card(card_, is_reversed_) -> void:
	if is_locked: return
	var types = card_.card_info.token_types.split(",")
	var values = card_.card_info.token_values.split(",")
	
	var suit = card_.card_info.suit
	
	if suit != "damage":
		change_token(suit, 1)
	
	for _i in types.size():
		var type = types[_i]
		var value = int(values[_i])
		
		if is_reversed_:
			value *= -1
		
		change_token(type, value)
		
		if type == "card":
			tablet.draw_from_deck(value)
	
func change_token(type_: String, value_: int) -> void:
	if type_ == "miss" or type_ == "card": return
	
	if type_ == "block":
		type_ = "hazard"
		value_ *= -1
	
	var token = get(type_ + "_token")
	token.value += value_
	
func get_token_value(type_: String) -> int:
	if type_ == "miss" or type_ == "card": return -1
	var token = get(type_ + "_token")
	return token.value
