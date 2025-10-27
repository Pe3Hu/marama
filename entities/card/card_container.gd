## Abstract base class for all card containers in the card framework.
##
## CardContainer provides the foundational functionality for managing collections of cards,
## including drag-and-drop operations, position management, and container interactions.
## All specialized containers (Hand, Pile, etc.) extend this class.
##
## Key Features:
## - Card collection management with position tracking
## - Drag-and-drop integration with DropZone system
## - History tracking for undo/redo operations
## - Extensible layout system through virtual methods
## - Visual debugging support for development
##
## Virtual Methods to Override:
## - _card_can_be_added(): Define container-specific rules
## - _update_target_positions(): Implement container layout logic
## - on_card_move_done(): Handle post-movement processing
##
## Usage:
## [codeblock]
## class_name MyContainer
## extends CardContainer
##
## func _card_can_be_added(cards: Array) -> bool:
##     return cards.size() == 1  # Only allow single cards
## [/codeblock]
class_name CardContainer
extends Control

# Static counter for unique container identification
static var next_id: int = 0


##
@export var tablet: Tablet
##
@export var bank: Bank
##
@export_group("drop_zone")
## Enables or disables the drop zone functionality.
@export var enable_drop_zone := true
@export_subgroup("Sensor")
## The size of the sensor. If not set, it will follow the size of the card.
@export var sensor_size: Vector2
## The position of the sensor.
@export var sensor_position: Vector2
## The texture used for the sensor.
@export var sensor_texture: Texture
## Determines whether the sensor is visible or not.
## Since the sensor can move following the status, please use it for debugging.
@export var sensor_visibility := false


# Container identification and management
var unique_id: int
var drop_zone_scene = preload("res://entities/field/drop_zone/drop_zone.tscn")
var drop_zone: DropZone = null

# Card collection and state
var _held_cards: Array[Card] = []
var _holding_cards: Array[Card] = []

# Scene references
var cards_node: Control
var card_manager: CardManager
var debug_mode := false


func _init() -> void:
	unique_id = next_id
	next_id += 1


func _ready() -> void:
	# Check if 'Cards' node already exists
	if has_node("Cards"):
		cards_node = $Cards
	else:
		cards_node = Control.new()
		cards_node.name = "Cards"
		cards_node.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(cards_node)
	
	var parent = get_parent()
	if parent is CardManager:
		card_manager = parent
	else:
		push_error("CardContainer should be under the CardManager")
		return
		
	card_manager._add_card_container(unique_id, self)
	
	if enable_drop_zone:
		drop_zone = drop_zone_scene.instantiate()
		add_child(drop_zone)
		drop_zone.init(self, [CardManager.CARD_ACCEPT_TYPE])
		# If sensor_size is not set, they will follow the card size.
		if sensor_size == Vector2(0, 0):
			sensor_size = card_manager.card_size
		drop_zone.set_sensor(sensor_size, sensor_position, sensor_texture, sensor_visibility)
		if debug_mode:
			drop_zone.sensor_outline.visible = true
		else:
			drop_zone.sensor_outline.visible = false


func _exit_tree() -> void:
	if card_manager != null:
		card_manager._delete_card_container(unique_id)


## Adds a card to this container at the specified index.
## @param card: The card to add
## @param index: Position to insert (-1 for end)
func add_card(card_: Card, index_: int = -1) -> void:
	if index_ == -1:
		_assign_card_to_container(card_)
	else:
		_insert_card_to_container(card_, index_)
	_move_object(card_, cards_node, index_)


## Removes a card from this container.
## @param card: The card to remove
## @returns: True if card was removed, false if not found
func remove_card(card_: Card) -> bool:
	var index = _held_cards.find(card_)
	if index != -1:
		_held_cards.remove_at(index)
	else:
		return false
	update_card_ui()
	return true

## Returns the number of contained cards
func get_card_count() -> int:
	return _held_cards.size()

## Checks if this container contains the specified card.
func has_card(card_: Card) -> bool:
	return _held_cards.has(card_)


## Removes all cards from this container.
func clear_cards() -> void:
	for card in _held_cards:
		_remove_object(card)
	_held_cards.clear()
	update_card_ui()


## Checks if the specified cards can be dropped into this container.
## Override _card_can_be_added() in subclasses for custom rules.
func check_card_can_be_dropped(cards_: Array) -> bool:
	if not enable_drop_zone: return false
	
	if drop_zone == null: return false
	
	if drop_zone.accept_types.has(CardManager.CARD_ACCEPT_TYPE) == false: return false
	
	if not drop_zone.check_mouse_is_in_drop_zone(): return false
	
	return _card_can_be_added(cards_)


func get_partition_index() -> int:
	var vertical_index = drop_zone.get_vertical_layers()
	if vertical_index != -1: return vertical_index
	
	var horizontal_index = drop_zone.get_horizontal_layers()
	if horizontal_index != -1: return horizontal_index
	
	return -1


## Shuffles the cards in this container using Fisher-Yates algorithm.
func shuffle() -> void:
	_fisher_yates_shuffle(_held_cards)
	for _i in range(_held_cards.size()):
		var card = _held_cards[_i]
		cards_node.move_child(card, _i)
	update_card_ui()


## Moves cards to this container with optional history tracking.
## @param cards: Array of cards to move
## @param index: Target position (-1 for end)
## @param with_history: Whether to record for undo
## @returns: True if move was successful
func move_cards(cards_: Array, index_: int = -1, with_history_: bool = true) -> bool:
	if not _card_can_be_added(cards_): return false
	# XXX: If the card is already in the container, we don't add it into the history.
	if not cards_.all(func(card): return _held_cards.has(card)) and with_history_:
		card_manager._add_history(self, cards_)
	_move_cards(cards_, index_)
	return true


## Restores cards to their original positions with index precision.
## @param cards: Cards to restore
## @param from_indices: Original indices for precise positioning
func undo(cards_: Array, from_indices_: Array = []) -> void:
	# Validate input parameters
	if not from_indices_.is_empty() and cards_.size() != from_indices_.size():
		push_error("Mismatched cards and indices arrays in undo operation!")
		# Fallback to basic undo
		_move_cards(cards_, -1)
		return
	
	# Fallback: add to end if no index info available
	if from_indices_.is_empty():
		_move_cards(cards_, -1)
		return
	
	# Validate all indices are valid
	for _i in range(from_indices_.size()):
		if from_indices_[_i] < 0:
			push_error("Invalid index found during undo: %d" % from_indices_[_i])
			# Fallback to basic undo
			_move_cards(cards_, -1)
			return
	
	# Check if indices are consecutive (bulk move scenario)
	var sorted_indices = from_indices_.duplicate()
	sorted_indices.sort()
	var is_consecutive = true
	for _i in range(1, sorted_indices.size()):
		if sorted_indices[_i] != sorted_indices[_i-1] + 1:
			is_consecutive = false
			break
	
	if is_consecutive and sorted_indices.size() > 1:
		# Bulk consecutive restore: maintain original relative order
		var lowest_index = sorted_indices[0]
		
		# Sort cards by their original indices to maintain proper order
		var card_index_pairs = []
		for _i in range(cards_.size()):
			card_index_pairs.append({"card": cards_[_i], "index": from_indices_[_i]})
		
		# Sort by index ascending to maintain original order
		card_index_pairs.sort_custom(func(a, b): return a.index < b.index)
		
		# Insert all cards starting from the lowest index
		for _i in range(card_index_pairs.size()):
			var target_index = min(lowest_index + _i, _held_cards.size())
			_move_cards([card_index_pairs[_i].card], target_index)
	else:
		# Non-consecutive indices: restore individually (original logic)
		var card_index_pairs = []
		for _i in range(cards_.size()):
			card_index_pairs.append({"card": cards_[_i], "index": from_indices_[_i], "original_order": _i})
		
		# Sort by index descending, then by original order ascending for stable sorting
		card_index_pairs.sort_custom(func(a, b): 
			if a.index == b.index: return a.original_order < b.original_order
			return a.index > b.index
		)
		
		# Restore each card to its original index
		for pair in card_index_pairs:
			var target_index = min(pair.index, _held_cards.size())  # Clamp to valid range
			_move_cards([pair.card], target_index)


func hold_card(card_: Card) -> void:
	if _held_cards.has(card_):
		_holding_cards.append(card_)


func release_holding_cards():
	if _holding_cards.is_empty(): return
	for card in _holding_cards:
		# Transition from HOLDING to IDLE state
		card.change_state(DraggableObject.DraggableState.IDLE)
	var copied_holding_cards = _holding_cards.duplicate()
	if card_manager != null:
		card_manager._on_drag_dropped(copied_holding_cards)
	_holding_cards.clear()


func get_string() -> String:
	return "card_container: %d" % unique_id


func on_card_move_done(_card: Card):
	pass


func on_card_pressed(_card: Card):
	pass


func _assign_card_to_container(card_: Card) -> void:
	if card_.card_container != self:
		card_.card_container = self
	if not _held_cards.has(card_):
		_held_cards.append(card_)
	update_card_ui()


func _insert_card_to_container(card_: Card, index_: int) -> void:
	if card_.card_container != self:
		card_.card_container = self
	if not _held_cards.has(card_):
		if index_ < 0:
			index_ = 0
		elif index_ > _held_cards.size():
			index_ = _held_cards.size()
		_held_cards.insert(index_, card_)
	update_card_ui()	


func _move_to_card_container(card_: Card, index_: int = -1, is_reversed_: bool = false) -> void:
	if card_.card_container != null:
		card_.card_container.remove_card(card_)
	add_card(card_, index_)


func _fisher_yates_shuffle(array_: Array) -> void:
	for _i in range(array_.size() - 1, 0, -1):
		var _j = randi() % (_i + 1)
		var temp = array_[_i]
		array_[_i] = array_[_j]
		array_[_j] = temp


func _move_cards(cards_: Array, index_: int = -1, is_reversed_: bool = false) -> void:
	var cur_index = index_
	for _i in range(cards_.size() - 1, -1, -1):
		var card = cards_[_i]
		if cur_index == -1:
			_move_to_card_container(card, index_, is_reversed_)
		else:
			_move_to_card_container(card, cur_index, is_reversed_)
			cur_index += 1


func _card_can_be_added(_cards: Array) -> bool:
	return true


## Updates the visual positions of all cards in this container.
## Call this after modifying card positions or container properties.
func update_card_ui() -> void:
	_update_target_z_index()
	_update_target_positions()


func _update_target_z_index() -> void:
	pass


func _update_target_positions() -> void:
	pass


func _move_object(target_: Node, to_: Node, index_: int = -1) -> void:
	if target_.get_parent() == to_:
		# If already the same parent, just change the order with move_child
		if index_ != -1:
			to_.move_child(target_, index_)
		else:
			# If index is -1, move to the last position
			to_.move_child(target_, to_.get_child_count() - 1)
		return

	var _global_position = target_.global_position
	if target_.get_parent() != null:
		target_.get_parent().remove_child(target_)
	if index_ != -1:
		to_.add_child(target_)
		to_.move_child(target_, index_)
	else:
		to_.add_child(target_)
	target_.global_position = _global_position


func _remove_object(target_: Node) -> void:
	var parent = target_.get_parent()
	if target_ != null:
		parent.remove_child(target_)
	target_.queue_free()
