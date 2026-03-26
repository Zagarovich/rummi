extends PanelContainer
class_name CardUI

signal card_clicked(card_data: Dictionary)
signal card_pressed(card_data: Dictionary)
signal card_released(card_data: Dictionary)

var data: Dictionary = {}
var is_selected: bool = false
var is_disabled: bool = false
var is_must_play: bool = false
var is_mini: bool = false
var is_face_down: bool = false
var is_new_drawn: bool = false

var _rank_tl: Label
var _suit_tl: Label
var _center: Label
var _rank_br: Label
var _suit_br: Label
var _joker_lbl: Label

var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _style_must: StyleBoxFlat
var _style_back: StyleBoxFlat
var _style_new_drawn: StyleBoxFlat
var _texture_rect: TextureRect

func _init():
	mouse_filter = MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_enter)
	mouse_exited.connect(_on_mouse_exit)

func _ready():
	_create_styles()
	_create_children()
	_update()

func _create_styles():
	# Базовый темный стиль (Premium Dark Mode)
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color("#181926") # Глубокий темный фон
	_corners(_style_normal, 10)
	_style_normal.border_color = Color("#363a4f") # Тонкий контур
	_style_normal.set_border_width_all(2)
	_style_normal.shadow_color = Color(0, 0, 0, 0.4)
	_style_normal.shadow_size = 8
	_style_normal.shadow_offset = Vector2(0, 4)

	# Выделенная карта (Neon Cyan Glow)
	_style_selected = _style_normal.duplicate()
	_style_selected.border_color = Color("#8aadf4")
	_style_selected.set_border_width_all(3)
	_style_selected.shadow_color = Color("#8aadf4", 0.3)
	_style_selected.shadow_size = 16

	# Карта, обязательная для хода (Neon Red/Pink Glow)
	_style_must = _style_normal.duplicate()
	_style_must.border_color = Color("#ed8796")
	_style_must.set_border_width_all(3)
	_style_must.shadow_color = Color("#ed8796", 0.4)
	_style_must.shadow_size = 18

	# Новая карта (Neon Green/Emerald Glow)
	_style_new_drawn = _style_normal.duplicate()
	_style_new_drawn.border_color = Color("#a6da95")
	_style_new_drawn.set_border_width_all(3)
	_style_new_drawn.shadow_color = Color("#a6da95", 0.35)
	_style_new_drawn.shadow_size = 16

	# Рубашка карты (Carbon/Tech Pattern)
	_style_back = StyleBoxFlat.new()
	_style_back.bg_color = Color("#11111b")
	_corners(_style_back, 10)
	_style_back.border_color = Color("#cba6f7") # Неоново-фиолетовый акцент
	_style_back.set_border_width_all(2)
	_style_back.shadow_color = Color(0, 0, 0, 0.6)
	_style_back.shadow_size = 10
	_style_back.shadow_offset = Vector2(0, 4)

func _corners(s: StyleBoxFlat, r: int):
	s.corner_radius_top_left = r
	s.corner_radius_top_right = r
	s.corner_radius_bottom_left = r
	s.corner_radius_bottom_right = r

func _create_children():
	# Верхний левый угол
	var tl = VBoxContainer.new()
	tl.add_theme_constant_override("separation", -6)
	add_child(tl)
	_rank_tl = Label.new()
	_suit_tl = Label.new()
	tl.add_child(_rank_tl)
	tl.add_child(_suit_tl)
	tl.position = Vector2(8, 6)

	# Центр
	_center = Label.new()
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_center)

	# Текстура карты
	_texture_rect = TextureRect.new()
	_texture_rect.set_anchors_preset(PRESET_FULL_RECT)
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_texture_rect)

	# Нижний правый угол
	var br = VBoxContainer.new()
	br.add_theme_constant_override("separation", -6)
	add_child(br)
	_rank_br = Label.new()
	_suit_br = Label.new()
	br.add_child(_rank_br)
	br.add_child(_suit_br)
	br.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	br.offset_left = -32
	br.offset_top = -55
	br.rotation = PI
	br.pivot_offset = Vector2(16, 24)

	# Джокер
	_joker_lbl = Label.new()
	_joker_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_joker_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_joker_lbl.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_joker_lbl)

func setup(p_data: Dictionary, p_sel: bool = false, p_dis: bool = false,
		p_must: bool = false, p_mini: bool = false, p_back: bool = false, p_new: bool = false):
	data = p_data
	is_selected = p_sel
	is_disabled = p_dis
	is_must_play = p_must
	is_mini = p_mini
	is_face_down = p_back
	is_new_drawn = p_new
	if is_inside_tree():
		_update()

func _update():
	# Размеры адаптированы под более вытянутый, изящный формат
	if is_mini:
		custom_minimum_size = Vector2(64, 96)
		size = Vector2(64, 96)
	else:
		custom_minimum_size = Vector2(100, 146)
		size = Vector2(100, 146)

	if is_face_down:
		add_theme_stylebox_override("panel", _style_back)
		_hide_all()
		_texture_rect.visible = false
		_center.text = "✦" # Современный минималистичный логотип рубашки
		_center.modulate = Color("#cba6f7")
		_center.add_theme_font_size_override("font_size", 48 if not is_mini else 32)
		modulate.a = 1.0
		return

	# Применение стилей обводки
	if is_must_play:
		add_theme_stylebox_override("panel", _style_must)
	elif is_selected:
		add_theme_stylebox_override("panel", _style_selected)
	elif is_new_drawn:
		add_theme_stylebox_override("panel", _style_new_drawn)
	else:
		add_theme_stylebox_override("panel", _style_normal)

	modulate.a = 0.5 if is_disabled else 1.0

	var suit = data.get("suit", "")
	
	# Отладка: если suit пустой, вывести данные карты
	if suit.is_empty() and not data.get("isJoker", false):
		print("Карта с пустой мастью: ", data)
	
	# ЧЕТЫРЕХЦВЕТНАЯ КОЛОДА (Стандарт современного онлайн-покера)
	var clr: Color
	match suit:
		"♥": clr = Color("#ed8796") # Мягкий неоновый красный
		"♦": clr = Color("#8aadf4") # Холодный синий
		"♣": clr = Color("#a6da95") # Яркий зеленый
		"♠": clr = Color("#cad3f5") # Чистый бело-серый
		_: clr = Color("#cad3f5")

	var fs = 14 if is_mini else 20
	var cfs = 42 if is_mini else 64

	if data.get("isJoker", false):
		_hide_all()
		var style_j = _style_normal.duplicate()
		style_j.border_color = Color("#f5a97f") # Оранжевый акцент для джокера
		add_theme_stylebox_override("panel", style_j)
		
		# Если джокеру назначены ранг и масть, показываем их текстом
		if data.has("jokerAssumedRank") and data.has("jokerAssumedSuit"):
			var jt = str(data.jokerAssumedRank) + "\n" + str(data.jokerAssumedSuit)
			_joker_lbl.text = jt
			_joker_lbl.add_theme_font_size_override("font_size", 24 if is_mini else 36)
			_joker_lbl.add_theme_color_override("font_color", Color("#f5a97f"))
			_joker_lbl.modulate.a = 1.0
			_texture_rect.visible = false
		else:
			# Для обычного джокера используем текстуру
			_joker_lbl.text = ""
			# Выбираем текстуру джокера на основе id (чётный/нечётный)
			var joker_num = 1
			if data.has("id"):
				var id_str = data.id
				var hash_val = id_str.hash()
				joker_num = (hash_val % 2) + 1  # 1 или 2
			var texture_path = "res://assets/cards/cards-png/Joker" + str(joker_num) + ".png"
			var texture = load(texture_path)
			if texture:
				_texture_rect.texture = texture
				_texture_rect.visible = true
			else:
				# fallback на текстовое представление
				_joker_lbl.text = "J\nO\nK\nE\nR"
				_joker_lbl.add_theme_font_size_override("font_size", 24 if is_mini else 36)
				_joker_lbl.add_theme_color_override("font_color", Color("#f5a97f"))
				_joker_lbl.modulate.a = 1.0
				_texture_rect.visible = false
	else:
		_joker_lbl.text = ""
		# Скрываем текстовые метки
		_rank_tl.visible = false
		_suit_tl.visible = false
		_rank_br.visible = false
		_suit_br.visible = false
		_center.visible = false
		
		# Определяем имя файла PNG
		var rank = data.get("rank", "")
		var filename = _card_filename(rank, suit)
		
		# Если имя файла пустое, используем текстовое представление
		if filename.is_empty():
			print("Пустое имя файла для карты: rank='", rank, "' suit='", suit, "' data=", data)
			# fallback на текстовое представление
			_rank_tl.visible = true
			_suit_tl.visible = true
			_rank_br.visible = true
			_suit_br.visible = true
			_center.visible = true
			var rank_str = str(rank)
			var suit_str = str(suit)
			_set_label(_rank_tl, rank_str, clr, fs)
			_set_label(_suit_tl, suit_str, clr, fs)
			_set_label(_rank_br, rank_str, clr, fs)
			_set_label(_suit_br, suit_str, clr, fs)
			var is_face = rank_str in ["В", "Д", "К", "Т", "J", "Q", "K", "A"]
			_center.text = rank_str if is_face else suit_str
			_center.add_theme_font_size_override("font_size", cfs)
			_center.add_theme_color_override("font_color", clr)
			_center.modulate.a = 0.15
			return
		
		var texture_path = "res://assets/cards/cards-png/" + filename + ".png"
		var texture = load(texture_path)
		if texture:
			_texture_rect.texture = texture
			_texture_rect.visible = true
		else:
			# fallback на текстовое представление
			_rank_tl.visible = true
			_suit_tl.visible = true
			_rank_br.visible = true
			_suit_br.visible = true
			_center.visible = true
			var rank_str = str(rank)
			var suit_str = str(suit)
			_set_label(_rank_tl, rank_str, clr, fs)
			_set_label(_suit_tl, suit_str, clr, fs)
			_set_label(_rank_br, rank_str, clr, fs)
			_set_label(_suit_br, suit_str, clr, fs)
			var is_face = rank_str in ["В", "Д", "К", "Т", "J", "Q", "K", "A"]
			_center.text = rank_str if is_face else suit_str
			_center.add_theme_font_size_override("font_size", cfs)
			_center.add_theme_color_override("font_color", clr)
			_center.modulate.a = 0.15

func _set_label(lbl: Label, txt: String, clr: Color, fs: int):
	lbl.text = txt
	lbl.add_theme_color_override("font_color", clr)
	lbl.add_theme_font_size_override("font_size", fs)
	# Добавляем современный шрифт с жирным начертанием, если нужно
	# lbl.add_theme_font_override("font", preload("res://your_bold_font.ttf"))

func _hide_all():
	_rank_tl.text = ""
	_suit_tl.text = ""
	_rank_br.text = ""
	_suit_br.text = ""
	_center.text = ""
	_joker_lbl.text = ""

func _card_filename(rank, suit) -> String:
	# Преобразует ранг и масть в имя файла SVG из Vector-Playing-Cards
	# Ранг: 2-10, J, Q, K, A
	# Масть: ♥ ♦ ♣ ♠ -> H, D, C, S
	var rank_str = str(rank)
	var suit_str = str(suit)
	# Преобразуем ранг
	if rank_str == "В": rank_str = "J" # Валет
	elif rank_str == "Д": rank_str = "Q" # Дама
	elif rank_str == "К": rank_str = "K" # Король
	elif rank_str == "Т": rank_str = "A" # Туз
	# Преобразуем масть
	var suit_letter = ""
	match suit_str:
		"♥": suit_letter = "H"
		"♦": suit_letter = "D"
		"♣": suit_letter = "C"
		"♠": suit_letter = "S"
		_: suit_letter = suit_str
	return rank_str + suit_letter

func _gui_input(event: InputEvent):
	if is_disabled: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			card_pressed.emit(data)
			card_clicked.emit(data)
		else:
			card_released.emit(data)

func _on_mouse_enter():
	if not is_disabled and not is_face_down:
		pivot_offset = size / 2.0
		# Более резкая и отзывчивая анимация
		var tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "scale", Vector2(1.06, 1.06), 0.1)

func _on_mouse_exit():
	var tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)