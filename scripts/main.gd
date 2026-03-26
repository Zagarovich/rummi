extends Control

var game: GameService

# ── UI Nodes ─────────────────────────────────────────────────────────────
var mode_panel: Panel
var multiplayer_panel: Panel
var multiplayer_refs: Dictionary = {}  # ссылки на элементы multiplayer панели
var lobby_panel: Panel

var msg_lbl: Label
var score_lbl: Label
var turn_lbl: Label

# Hand + Meld zones per player (index 0 = human, 1-3 = bots)
var hand_areas: Array = []
var meld_areas: Array = []
var bot_panels: Array = []   # highlight panels for bots

var center_right: Control
var deck_btn: Button
var deck_count: Label
var pool_area: Control
var pool_count: Label
var take_btn: Button

var actions_box: VBoxContainer
var play_btn: Button
var discard_btn: Button
var sort_btn: Button
var undo_btn: Button

var round_panel: Panel
var round_msg: Label
var round_btn: Button

var joker_panel: Panel
var joker_opts_container: Container

# ── State ─────────────────────────────────────────────────────────────────
var sel_hand: Array = []
var sel_discard: int = -1
var pend_type: String = ""
var pend_joker: Dictionary = {}
var pend_meld: String = ""
var highlighted_meld_id: String = ""

const CARD_W := 96
const CARD_H := 139
const MINI_W := 62
const MINI_H := 91

# ════════════════════════════════════════════════════════════════════════
# INIT
# ════════════════════════════════════════════════════════════════════════
func _ready():
	_build()
	game = GameService.new()
	add_child(game)
	game.state_changed.connect(_refresh)
	mode_panel.show()
	
	# Connect NetworkManager signals
	NetworkManager.player_list_changed.connect(_update_players_list)
	NetworkManager.game_ready.connect(_on_multiplayer_game_ready)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.host_disconnected.connect(_on_host_disconnected)

# ════════════════════════════════════════════════════════════════════════
# STYLE HELPERS
# ════════════════════════════════════════════════════════════════════════
func _mk_flat(bg: Color, radius: int = 12, border: Color = Color.TRANSPARENT, bw: int = 0) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius; s.corner_radius_bottom_right = radius
	if bw > 0:
		s.border_color = border; s.set_border_width_all(bw)
	return s

func _mk_btn(txt: String, bg: Color, w: float = 130, h: float = 52, radius: int = 30, fs: int = 15) -> Button:
	var b = Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(w, h)
	# Normal style with soft shadow and subtle border
	var ns = _mk_flat(bg, radius)
	ns.shadow_color = Color(0, 0, 0, 0.2)
	ns.shadow_size = 12
	ns.shadow_offset = Vector2(0, 6)
	ns.border_color = bg.lightened(0.2)
	ns.set_border_width_all(1)
	# Hover style - lighter with stronger shadow
	var hs = _mk_flat(bg.lightened(0.15), radius)
	hs.shadow_color = Color(0, 0, 0, 0.25)
	hs.shadow_size = 14
	hs.shadow_offset = Vector2(0, 7)
	hs.border_color = bg.lightened(0.3)
	hs.set_border_width_all(1)
	# Pressed style - darker
	var ps = _mk_flat(bg.darkened(0.12), radius)
	ps.shadow_color = Color(0, 0, 0, 0.15)
	ps.shadow_size = 8
	ps.shadow_offset = Vector2(0, 3)
	ps.border_color = bg.darkened(0.2)
	ps.set_border_width_all(1)
	# Disabled style - muted gray
	var ds = _mk_flat(Color("#374151"), radius)
	ds.border_color = Color("#4b5563")
	ds.set_border_width_all(1)
	
	b.add_theme_stylebox_override("normal", ns)
	b.add_theme_stylebox_override("hover", hs)
	b.add_theme_stylebox_override("pressed", ps)
	b.add_theme_stylebox_override("disabled", ds)
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", Color("#ffffff"))
	b.add_theme_color_override("font_color_disabled", Color("#9ca3af"))
	return b

func _corners(s: StyleBoxFlat, r: int):
	s.corner_radius_top_left = r; s.corner_radius_top_right = r
	s.corner_radius_bottom_left = r; s.corner_radius_bottom_right = r

func _lbl(txt: String, fs: int, clr: Color, _bold: bool = false) -> Label:
	var l = Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", clr)
	return l

# ════════════════════════════════════════════════════════════════════════
# BUILD UI
# ════════════════════════════════════════════════════════════════════════
func _build():
	# Background gradient via two rects
	var bg_bot = ColorRect.new()
	bg_bot.color = Color("#0f172a")
	bg_bot.set_anchors_preset(PRESET_FULL_RECT)
	bg_bot.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg_bot)

	var bg_top = ColorRect.new()
	bg_top.color = Color("#1e293b", 0.8)
	bg_top.set_anchors_preset(PRESET_TOP_WIDE)
	bg_top.anchor_bottom = 0.5
	bg_top.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg_top)

	_build_header()
	_build_player_zones()
	_build_center()
	_build_actions()
	_build_mode_panel()
	_build_multiplayer_panel()
	_build_lobby()
	_build_round_panel()
	_build_joker_panel()

# ── Header ──────────────────────────────────────────────────────────────
func _build_header():
	var header = HBoxContainer.new()
	header.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	header.offset_left = 16; header.offset_right = -16
	header.offset_top = 8; header.offset_bottom = 44
	header.add_theme_constant_override("separation", 12)
	add_child(header)

	var title = _lbl("TACTICAL RUMMY", 20, Color("#fbbf24"))
	header.add_child(title)

	turn_lbl = Label.new()
	turn_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	turn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_lbl.add_theme_font_size_override("font_size", 13)
	turn_lbl.add_theme_color_override("font_color", Color("#38bdf8"))
	header.add_child(turn_lbl)

	score_lbl = Label.new()
	score_lbl.add_theme_font_size_override("font_size", 13)
	score_lbl.add_theme_color_override("font_color", Color("#34d399"))
	header.add_child(score_lbl)

	var exit_btn = _mk_btn("✕", Color("#ef4444"), 40, 32, 20, 14)
	exit_btn.tooltip_text = "В лобби"
	exit_btn.pressed.connect(func():
		game.phase = "GAME_OVER"; _clear_sel(); lobby_panel.show(); lobby_panel.move_to_front()
	)
	header.add_child(exit_btn)

	msg_lbl = Label.new()
	msg_lbl.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	msg_lbl.offset_top = 44; msg_lbl.offset_bottom = 66
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_lbl.add_theme_font_size_override("font_size", 14)
	msg_lbl.add_theme_color_override("font_color", Color("#fef3c7"))
	add_child(msg_lbl)

# ── Player zones ────────────────────────────────────────────────────────
func _build_player_zones():
	for i in range(4):
		var ha = Control.new()
		ha.mouse_filter = MOUSE_FILTER_IGNORE
		var ma = Control.new()
		ma.mouse_filter = MOUSE_FILTER_IGNORE

		if i == 0:  # Human – bottom
			ha.anchor_left = 0.0; ha.anchor_right = 1.0
			ha.anchor_top = 0.82; ha.anchor_bottom = 1.0
			ma.anchor_left = 0.01; ma.anchor_right = 0.99
			ma.anchor_top = 0.50; ma.anchor_bottom = 0.80
		elif i == 1:  # Bot 1 – top-left
			ha.anchor_left = 0.0; ha.anchor_right = 0.34
			ha.anchor_top = 0.065; ha.anchor_bottom = 0.20
			ma.anchor_left = 0.0; ma.anchor_right = 0.33
			ma.anchor_top = 0.20; ma.anchor_bottom = 0.40
		elif i == 2:  # Bot 2 – top-center
			ha.anchor_left = 0.33; ha.anchor_right = 0.67
			ha.anchor_top = 0.065; ha.anchor_bottom = 0.20
			ma.anchor_left = 0.33; ma.anchor_right = 0.67
			ma.anchor_top = 0.20; ma.anchor_bottom = 0.40
		elif i == 3:  # Bot 3 – top-right
			ha.anchor_left = 0.66; ha.anchor_right = 1.0
			ha.anchor_top = 0.065; ha.anchor_bottom = 0.20
			ma.anchor_left = 0.67; ma.anchor_right = 1.0
			ma.anchor_top = 0.20; ma.anchor_bottom = 0.40

		# Bot background panel
		if i > 0:
			var bp = Panel.new()
			bp.mouse_filter = MOUSE_FILTER_IGNORE
			bp.anchor_left = ha.anchor_left; bp.anchor_right = ha.anchor_right
			bp.anchor_top = ha.anchor_top - 0.005; bp.anchor_bottom = ha.anchor_bottom
			var bps = _mk_flat(Color("#1e293b", 0.15), 15, Color("#334155", 0.3), 1)
			bp.add_theme_stylebox_override("panel", bps)
			add_child(bp)
			bot_panels.append(bp)

		add_child(ha); add_child(ma)
		hand_areas.append(ha); meld_areas.append(ma)

# ── Center (Deck + Pool) ─────────────────────────────────────────────────
func _build_center():
	center_right = Control.new()
	center_right.mouse_filter = MOUSE_FILTER_IGNORE
	center_right.anchor_left = 0.04; center_right.anchor_right = 0.96
	center_right.anchor_top = 0.40; center_right.anchor_bottom = 0.55
	add_child(center_right)

	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(PRESET_FULL_RECT)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 28)
	center_right.add_child(hbox)

	# Reserve (Deck)
	var res_vbox = VBoxContainer.new()
	res_vbox.add_theme_constant_override("separation", 6)
	res_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(res_vbox)

	deck_count = Label.new()
	deck_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	deck_count.add_theme_font_size_override("font_size", 12)
	deck_count.add_theme_color_override("font_color", Color("#38bdf8"))
	res_vbox.add_child(deck_count)

	deck_btn = Button.new()
	deck_btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
	deck_btn.text = "♠"
	var db_n = _mk_flat(Color("#1e293b"), 12, Color("#38bdf8"), 2)
	db_n.shadow_color = Color(0,0,0,0.4); db_n.shadow_size = 6
	deck_btn.add_theme_stylebox_override("normal", db_n)
	deck_btn.add_theme_stylebox_override("hover", _mk_flat(Color("#334155"), 12, Color("#60a5fa"), 2))
	deck_btn.add_theme_color_override("font_color", Color("#38bdf8"))
	deck_btn.add_theme_font_size_override("font_size", 36)
	deck_btn.pressed.connect(_on_deck)
	res_vbox.add_child(deck_btn)

	# Pool (Discard pile)
	var pool_vbox = VBoxContainer.new()
	pool_vbox.add_theme_constant_override("separation", 6)
	pool_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(pool_vbox)

	pool_count = Label.new()
	pool_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pool_count.add_theme_font_size_override("font_size", 12)
	pool_count.add_theme_color_override("font_color", Color("#38bdf8"))
	pool_vbox.add_child(pool_count)

	pool_area = Control.new()
	pool_area.custom_minimum_size = Vector2(CARD_W + 80, CARD_H)
	pool_vbox.add_child(pool_area)

	take_btn = _mk_btn("↑ Взять", Color("#0369a1"), 100, 40, 20, 14)
	take_btn.pressed.connect(_on_take_pool)
	pool_vbox.add_child(take_btn)

# ── Action buttons ────────────────────────────────────────────────────────
func _build_actions():
	actions_box = VBoxContainer.new()
	actions_box.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	actions_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	actions_box.offset_left = 12
	actions_box.offset_top = -310
	actions_box.offset_bottom = -12
	actions_box.alignment = BoxContainer.ALIGNMENT_END
	actions_box.add_theme_constant_override("separation", 10)
	add_child(actions_box)

	play_btn = _mk_btn("▶ Выложить", Color("#059669"), 130, 50, 25)
	discard_btn = _mk_btn("✕ Сбросить", Color("#0f4c75"), 130, 50, 25)
	sort_btn = _mk_btn("⇅ Сортировка", Color("#374151"), 130, 44, 22, 13)
	undo_btn = _mk_btn("↺ Отменить", Color("#0369a1"), 130, 44, 22, 13)

	play_btn.pressed.connect(_on_play)
	discard_btn.pressed.connect(_on_discard)
	sort_btn.pressed.connect(_on_sort)
	undo_btn.pressed.connect(_on_undo_draw)

	actions_box.add_child(play_btn)
	actions_box.add_child(discard_btn)
	actions_box.add_child(sort_btn)
	actions_box.add_child(undo_btn)

# ── Mode selection ─────────────────────────────────────────────────────────
func _build_mode_panel():
	mode_panel = Panel.new()
	mode_panel.set_anchors_preset(PRESET_FULL_RECT)
	mode_panel.add_theme_stylebox_override("panel", _mk_flat(Color("#0f172a", 0.95), 0))
	add_child(mode_panel)
	
	var cc = CenterContainer.new(); cc.set_anchors_preset(PRESET_FULL_RECT); mode_panel.add_child(cc)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 28)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(vb)
	
	# Title
	var title = _lbl("TACTICAL RUMMY", 54, Color("#fbbf24"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_color_override("font_outline_color", Color(0,0,0,0.4))
	vb.add_child(title)
	
	var sub = _lbl("♠ ♥  Multiplayer Card Game  ♦ ♣", 16, Color("#38bdf8"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	
	# Buttons
	var single_btn = _mk_btn("▶  ОДИНОЧНАЯ ИГРА", Color("#059669"), 280, 68, 34, 22)
	single_btn.pressed.connect(func():
		mode_panel.hide()
		lobby_panel.show()
	)
	vb.add_child(single_btn)
	
	var host_btn = _mk_btn("🌐  СОЗДАТЬ КОМНАТУ", Color("#0369a1"), 280, 68, 34, 22)
	host_btn.pressed.connect(func():
		mode_panel.hide()
		_show_multiplayer_panel(true)
	)
	vb.add_child(host_btn)
	
	var join_btn = _mk_btn("🔗  ПРИСОЕДИНИТЬСЯ", Color("#7c3aed"), 280, 68, 34, 22)
	join_btn.pressed.connect(func():
		mode_panel.hide()
		_show_multiplayer_panel(false)
	)
	vb.add_child(join_btn)
	
	var exit_btn = _mk_btn("✕  ВЫХОД", Color("#374151"), 200, 56, 28, 20)
	exit_btn.pressed.connect(func(): get_tree().quit())
	vb.add_child(exit_btn)

# ── Multiplayer panel ──────────────────────────────────────────────────────
func _build_multiplayer_panel():
	multiplayer_panel = Panel.new()
	multiplayer_panel.set_anchors_preset(PRESET_FULL_RECT)
	multiplayer_panel.add_theme_stylebox_override("panel", _mk_flat(Color(0.02, 0.09, 0.05, 0.97), 0))
	multiplayer_panel.hide()
	add_child(multiplayer_panel)
	
	var cc = CenterContainer.new(); cc.set_anchors_preset(PRESET_FULL_RECT); multiplayer_panel.add_child(cc)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(vb)
	
	# Title
	var title = Label.new()
	title.text = "🌐  МУЛЬТИПЛЕЕР"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("#60a5fa"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	
	# Name input
	var name_hbox = HBoxContainer.new()
	name_hbox.add_theme_constant_override("separation", 10)
	vb.add_child(name_hbox)
	
	var name_label = _lbl("Имя:", 18, Color("#a7f3d0"))
	name_hbox.add_child(name_label)
	
	var name_input = LineEdit.new()
	name_input.placeholder_text = "Игрок"
	name_input.custom_minimum_size = Vector2(200, 40)
	name_input.text = "Игрок"
	name_hbox.add_child(name_input)
	
	# IP input (for client)
	var ip_hbox = HBoxContainer.new()
	ip_hbox.add_theme_constant_override("separation", 10)
	ip_hbox.visible = false  # Hidden for host
	vb.add_child(ip_hbox)
	
	var ip_label = _lbl("IP:", 18, Color("#a7f3d0"))
	ip_hbox.add_child(ip_label)
	
	var ip_input = LineEdit.new()
	ip_input.placeholder_text = "192.168.1.100"
	ip_input.custom_minimum_size = Vector2(200, 40)
	ip_input.text = "127.0.0.1"
	ip_hbox.add_child(ip_input)
	
	# Player list
	var players_label = _lbl("Игроки:", 18, Color("#a7f3d0"))
	players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(players_label)
	
	var players_list = VBoxContainer.new()
	players_list.custom_minimum_size = Vector2(250, 120)
	var players_list_style = _mk_flat(Color("#0b3320", 0.8), 10, Color("#1d6b46"), 1)
	players_list.add_theme_stylebox_override("panel", players_list_style)
	vb.add_child(players_list)
	
	# Buttons
	var buttons_hbox = HBoxContainer.new()
	buttons_hbox.add_theme_constant_override("separation", 15)
	vb.add_child(buttons_hbox)
	
	var action_btn = _mk_btn("СОЗДАТЬ", Color("#059669"), 140, 56, 28, 20)
	buttons_hbox.add_child(action_btn)
	
	var back_btn = _mk_btn("← НАЗАД", Color("#374151"), 140, 56, 28, 20)
	back_btn.pressed.connect(func():
		multiplayer_panel.hide()
		mode_panel.show()
		NetworkManager.disconnect_all()
	)
	buttons_hbox.add_child(back_btn)
	
	# Start game button (host only)
	var start_btn = _mk_btn("▶ НАЧАТЬ ИГРУ", Color("#f59e0b"), 200, 60, 30, 22)
	start_btn.visible = false
	start_btn.pressed.connect(_on_start_game_pressed)
	vb.add_child(start_btn)
	
	# Store references
	multiplayer_refs["name_input"] = name_input
	multiplayer_refs["ip_input"] = ip_input
	multiplayer_refs["ip_hbox"] = ip_hbox
	multiplayer_refs["players_list"] = players_list
	multiplayer_refs["action_btn"] = action_btn
	multiplayer_refs["start_btn"] = start_btn

func _show_multiplayer_panel(is_host_mode: bool):
	multiplayer_panel.show()
	multiplayer_refs["ip_hbox"].visible = not is_host_mode
	
	if is_host_mode:
		multiplayer_refs["action_btn"].text = "СОЗДАТЬ КОМНАТУ"
		multiplayer_refs["action_btn"].add_theme_stylebox_override("normal", _mk_flat(Color("#059669"), 28))
		multiplayer_refs["action_btn"].pressed.connect(_on_host_pressed, CONNECT_ONE_SHOT)
	else:
		multiplayer_refs["action_btn"].text = "ПРИСОЕДИНИТЬСЯ"
		multiplayer_refs["action_btn"].add_theme_stylebox_override("normal", _mk_flat(Color("#7c3aed"), 28))
		multiplayer_refs["action_btn"].pressed.connect(_on_join_pressed, CONNECT_ONE_SHOT)
	
	multiplayer_refs["start_btn"].visible = is_host_mode
	_update_players_list()

func _on_host_pressed():
	var player_name = multiplayer_refs["name_input"].text.strip_edges()
	if player_name.is_empty():
		player_name = "Хост"
	
	var err = NetworkManager.host_game(player_name)
	if err != OK:
		msg_lbl.text = "Ошибка создания комнаты: %d" % err
	else:
		multiplayer_refs["action_btn"].disabled = true
		msg_lbl.text = "Комната создана. Ожидание игроков..."

func _on_join_pressed():
	var player_name = multiplayer_refs["name_input"].text.strip_edges()
	if player_name.is_empty():
		player_name = "Игрок"
	
	var ip = multiplayer_refs["ip_input"].text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	
	var err = NetworkManager.join_game(ip, player_name)
	if err != OK:
		msg_lbl.text = "Ошибка подключения: %d" % err
	else:
		multiplayer_refs["action_btn"].disabled = true
		msg_lbl.text = "Подключение..."

func _update_players_list():
	if not multiplayer_panel or not multiplayer_panel.visible:
		return
	
	# Clear list
	for child in multiplayer_refs["players_list"].get_children():
		child.queue_free()
	
	# Add players from NetworkManager
	for peer_id in NetworkManager.peer_names:
		var player_name = NetworkManager.peer_names[peer_id]
		var label = _lbl("• " + player_name, 16, Color("#d1fae5"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		multiplayer_refs["players_list"].add_child(label)
	
	# Update start button state (host only)
	if multiplayer_refs["start_btn"].visible:
		var player_count = NetworkManager.get_player_count()
		multiplayer_refs["start_btn"].disabled = player_count < 2
		if player_count < 2:
			multiplayer_refs["start_btn"].tooltip_text = "Нужно минимум 2 игрока"
		else:
			multiplayer_refs["start_btn"].tooltip_text = "Начать игру с %d игроками" % player_count

# ── Lobby ─────────────────────────────────────────────────────────────────
func _build_lobby():
	lobby_panel = Panel.new()
	lobby_panel.set_anchors_preset(PRESET_FULL_RECT)
	lobby_panel.add_theme_stylebox_override("panel", _mk_flat(Color("#0f172a", 0.95), 0))
	add_child(lobby_panel)

	var cc = CenterContainer.new(); cc.set_anchors_preset(PRESET_FULL_RECT); lobby_panel.add_child(cc)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 28)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(vb)

	# Title
	var title = _lbl("TACTICAL RUMMY", 54, Color("#fbbf24"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_color_override("font_outline_color", Color(0,0,0,0.4))
	vb.add_child(title)

	var sub = _lbl("♠ ♥  Multiplayer Card Game  ♦ ♣", 16, Color("#38bdf8"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	# Play button
	var start = _mk_btn("▶  ИГРАТЬ", Color("#059669"), 240, 68, 34, 26)
	start.pressed.connect(func():
		lobby_panel.hide()
		game.start_game(1)
	)
	vb.add_child(start)

# ── Round / Game over panel ───────────────────────────────────────────────
func _build_round_panel():
	round_panel = Panel.new()
	round_panel.set_anchors_preset(PRESET_FULL_RECT)
	round_panel.add_theme_stylebox_override("panel", _mk_flat(Color("#0f172a", 0.9), 0))
	round_panel.hide(); add_child(round_panel)

	var cc = CenterContainer.new(); cc.set_anchors_preset(PRESET_FULL_RECT); round_panel.add_child(cc)
	var wrap_container = PanelContainer.new()
	var ws = _mk_flat(Color("#1e293b"), 20, Color("#38bdf8"), 2)
	ws.content_margin_left = 36; ws.content_margin_right = 36
	ws.content_margin_top = 32; ws.content_margin_bottom = 32
	wrap_container.add_theme_stylebox_override("panel", ws); cc.add_child(wrap_container)

	var box = VBoxContainer.new(); box.add_theme_constant_override("separation", 20); wrap_container.add_child(box)
	round_msg = Label.new()
	round_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_msg.add_theme_font_size_override("font_size", 22)
	round_msg.add_theme_color_override("font_color", Color("#f1f5f9"))
	box.add_child(round_msg)

	round_btn = _mk_btn("Продолжить", Color("#059669"), 220, 56, 28, 20)
	round_btn.pressed.connect(_on_continue)
	box.add_child(round_btn)

# ── Joker panel ────────────────────────────────────────────────────────────
func _build_joker_panel():
	joker_panel = Panel.new()
	joker_panel.set_anchors_preset(PRESET_FULL_RECT)
	joker_panel.add_theme_stylebox_override("panel", _mk_flat(Color("#0f172a", 0.92), 0))
	joker_panel.hide(); add_child(joker_panel)

	var cc = CenterContainer.new(); cc.set_anchors_preset(PRESET_FULL_RECT); joker_panel.add_child(cc)
	var wrap_container = PanelContainer.new()
	var ws = _mk_flat(Color("#1e293b"), 20, Color("#38bdf8"), 2)
	ws.content_margin_left = 28; ws.content_margin_right = 28
	ws.content_margin_top = 28; ws.content_margin_bottom = 28
	wrap_container.add_theme_stylebox_override("panel", ws); cc.add_child(wrap_container)

	var vb = VBoxContainer.new(); vb.add_theme_constant_override("separation", 18); wrap_container.add_child(vb)
	var t = Label.new()
	t.text = "🃏  Настройка Джокера"
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color("#fbbf24"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)

	joker_opts_container = HFlowContainer.new()
	joker_opts_container.custom_minimum_size = Vector2(300, 60)
	joker_opts_container.add_theme_constant_override("h_separation", 10)
	joker_opts_container.add_theme_constant_override("v_separation", 10)
	vb.add_child(joker_opts_container)

	var cancel = _mk_btn("Отмена", Color("#374151"), 150, 46, 23, 16)
	cancel.pressed.connect(func(): joker_panel.hide(); _clear_sel())
	vb.add_child(cancel)

# ════════════════════════════════════════════════════════════════════════
# STATE REFRESH
# ════════════════════════════════════════════════════════════════════════
func _refresh():
	if not is_inside_tree() or game.players.is_empty(): return
	var cp = game.get_current_player()

	# Header info
	var score_str = "Раунд %d | " % game.round_number
	for p in game.players: score_str += "%s: %d  " % [p.name, p.globalScore]
	score_lbl.text = score_str.strip_edges()

	if cp.get("isBot", false):
		turn_lbl.text = "▶ Ход: %s" % cp.name
	else:
		var phase_name = {"DRAW": "Берите карту", "ACTION": "Ход игрока", "DISCARD": "Сбросьте карту"}.get(game.phase, "")
		turn_lbl.text = "▶ Вы — %s" % phase_name

	msg_lbl.text = game.message

	deck_count.text = "РЕЗЕРВ  %d" % game.deck.size()
	deck_btn.modulate.a = 1.0 if game.phase == "DRAW" and not cp.get("isBot", false) else 0.35
	pool_count.text = "ПУЛ  %d" % game.discard_pile.size()

	# Draw player zones
	for i in range(4):
		_clear(hand_areas[i])
		_clear(meld_areas[i])
		if i < game.players.size():
			_draw_fan_at(hand_areas[i], game.players[i].hand, i)
			_draw_melds_for(meld_areas[i], game.players[i].id)

	# Highlight active bot panel
	for bi in range(bot_panels.size()):
		var active = (bi + 1 < game.players.size() and game.players[bi + 1].id == cp.id)
		var panel_style = _mk_flat(
			Color("#10b981", 0.12) if active else Color(1,1,1,0.03),
			10,
			Color("#10b981", 0.8) if active else Color(1,1,1,0.06),
			1 if not active else 2
		)
		bot_panels[bi].add_theme_stylebox_override("panel", panel_style)

	_draw_pool()

	var can_act = game.phase in ["ACTION", "DISCARD"] and not cp.get("isBot", false)
	play_btn.disabled = not (can_act and sel_hand.size() >= 3)
	discard_btn.disabled = not (can_act and sel_hand.size() == 1)
	sort_btn.modulate.a = 1.0 if (game.phase != "DRAW" or true) else 0.5
	take_btn.visible = (sel_discard != -1 and game.phase == "DRAW" and not cp.get("isBot", false))
	take_btn.disabled = not (sel_discard != -1 and game.can_draw_from_discard(sel_discard))
	undo_btn.disabled = not game.can_undo_draw()

	if game.phase in ["ROUND_OVER", "GAME_OVER"]:
		var ms = ("🏆 Победа!\n" if game.phase == "GAME_OVER" else "Раунд завершен!\n")
		for p in game.players:
			ms += "%s: %d очков\n" % [p.name, p.globalScore]
		round_msg.text = ms.strip_edges()
		round_btn.text = "Новая игра" if game.phase == "GAME_OVER" else "Далее"
		round_panel.show(); round_panel.move_to_front()
	else:
		round_panel.hide()

# ── Fan drawing ───────────────────────────────────────────────────────────
func _draw_fan_at(area: Control, hand: Array, pos_idx: int):
	var n = hand.size()
	if n == 0: return

	var area_rect = area.get_rect()
	var ax = area_rect.size.x if area_rect.size.x > 0 else get_viewport_rect().size.x
	var ay = area_rect.size.y if area_rect.size.y > 0 else get_viewport_rect().size.y * 0.25

	if pos_idx == 0:
		# Human: large fan with arc
		var overlap = clampf(CARD_W * 0.90, 18, 100)
		var total_w = CARD_W + (n - 1) * overlap
		var max_angle = min(deg_to_rad(28), deg_to_rad(n * 3.5))
		var start_x = ax / 2.0 - total_w / 2.0
		for i in n:
			var cdata = hand[i]
			var card = CardUI.new()
			area.add_child(card)
			var is_sel = false
			for s in sel_hand:
				if s.id == cdata.id: is_sel = true; break
			var must = (cdata.id == game.must_play_card_id)
			var new_drawn = cdata.get("isNewDrawn", false)
			card.setup(cdata, is_sel, false, must, false, false, new_drawn)
			var t = 0.0
			if n > 1: t = float(i) / float(n - 1) * 2.0 - 1.0
			var angle = t * max_angle * 0.5
			var arc = abs(t) * abs(t) * 22.0
			card.position = Vector2(start_x + i * overlap, arc)
			card.rotation = angle
			card.pivot_offset = Vector2(CARD_W / 2.0, CARD_H)
			if is_sel: card.position.y -= 24
			card.z_index = i
			card.card_clicked.connect(_on_hand_click)
	else:
		# Bot: horizontal mini fan, face-down
		var bw = MINI_W
		var bot_overlap = clampf(bw * 0.87, 10, 40)
		var total_w = bw + (n - 1) * bot_overlap
		var start_x = ax / 2.0 - total_w / 2.0
		var start_y = (ay - MINI_H) / 2.0
		for i in n:
			var cdata = hand[i]
			var card = CardUI.new()
			area.add_child(card)
			card.setup(cdata, false, false, false, true, true)
			card.position = Vector2(start_x + i * bot_overlap, start_y)
			card.z_index = i

# ── Pool ──────────────────────────────────────────────────────────────────
func _draw_pool():
	_clear(pool_area)
	var dp = game.discard_pile
	var count = dp.size()
	for i in range(count - 1, -1, -1):
		var card = CardUI.new()
		pool_area.add_child(card)
		var is_sel_pool = (i == sel_discard)
		card.setup(dp[i], is_sel_pool, game.phase != "DRAW", false, false, false)
		card.position = Vector2((count - 1 - i) * 30, 0)
		card.z_index = count - 1 - i
		var ci = i
		card.card_clicked.connect(func(_d):
			if game.phase != "DRAW" or game.get_current_player().get("isBot", false): return
			sel_discard = ci if sel_discard != ci else -1
			highlighted_meld_id = ""
			_refresh()
		)

# ── Melds ──────────────────────────────────────────────────────────────────
func _draw_melds_for(container: Control, pid: int):
	var is_human_zone = (pid == game.players[0].id if game.players.size() > 0 else false)
	var mw = 65 if is_human_zone else 50
	var mh = 94 if is_human_zone else 74
	var m_ov = 30 if is_human_zone else 23

	# Track auto-positioning
	var x_cursor = 4
	var y_cursor = 4
	var row_h = mh + 26
	const ROW_MAX = 300.0

	for m in game.melds:
		var my_cards = m.cards.filter(func(c): return c.get("ownerId", m.ownerId) == pid)
		if my_cards.is_empty(): continue

		var n = my_cards.size()
		var total_w = mw + (n - 1) * m_ov + 8
		var total_h = mh + 24

		var meld_ctrl = Control.new()
		meld_ctrl.custom_minimum_size = Vector2(total_w, total_h)

		# Meld label with colored badge
		var meld_lbl_text = ""
		var lbl_color = Color("#fbbf24")
		if my_cards.any(func(c): return c.get("isSwapped", false)):
			meld_lbl_text = "+ВЫКУП"; lbl_color = Color("#f97316")
		elif n == m.cards.size():
			meld_lbl_text = "СЕКВ" if m.type == "RUN" else "СЕТ"
			lbl_color = Color("#34d399") if m.type == "RUN" else Color("#60a5fa")
		else:
			meld_lbl_text = "+ДОЛОЖ."; lbl_color = Color("#f97316")

		var lbl = Label.new()
		lbl.text = meld_lbl_text
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", lbl_color)
		lbl.position = Vector2(2, 0)
		meld_ctrl.add_child(lbl)

		var max_angle = min(deg_to_rad(22), deg_to_rad(n * 4.0))

		for ci in n:
			var c = my_cards[ci]
			var card = CardUI.new()
			meld_ctrl.add_child(card)

			var is_highlighted = (m.id == highlighted_meld_id)
			card.setup(c, is_highlighted, false, false, true, false)

			if not is_human_zone:
				card.scale = Vector2(0.84, 0.84)

			var t = 0.0
			if n > 1: t = float(ci) / float(n - 1) * 2.0 - 1.0
			var angle = t * max_angle * 0.5
			var arc = abs(t) * abs(t) * 10.0

			card.position = Vector2(4 + ci * m_ov, 14 + arc)
			card.rotation = angle
			card.pivot_offset = Vector2(mw / 2.0, mh)
			card.z_index = ci

			var mid = m.id
			card.card_clicked.connect(func(d):
				if game.phase == "ACTION" and not game.get_current_player().get("isBot", false) and (pend_type != "" or sel_hand.size() == 1):
					_on_table_click(mid, d)
			)
			card.card_pressed.connect(func(_d):
				if (game.phase != "ACTION" or game.get_current_player().get("isBot", false) or sel_hand.is_empty()):
					highlighted_meld_id = mid; _refresh()
			)
			card.card_released.connect(func(_d):
				if highlighted_meld_id == mid:
					highlighted_meld_id = ""; _refresh()
			)

		# Position meld_ctrl in a free-flow grid
		if x_cursor + total_w > ROW_MAX and x_cursor > 4:
			x_cursor = 4; y_cursor += row_h
		meld_ctrl.position = Vector2(x_cursor, y_cursor)
		x_cursor += total_w + 6

		container.add_child(meld_ctrl)

# ════════════════════════════════════════════════════════════════════════
# HANDLERS
# ════════════════════════════════════════════════════════════════════════
func _clear(node: Node):
	for c in node.get_children():
		c.queue_free()

func _on_deck():
	if game.phase == "DRAW" and not game.get_current_player().get("isBot", false):
		game.net_draw_deck(); _clear_sel()

func _on_take_pool():
	if sel_discard != -1:
		game.net_draw_discard(sel_discard); _clear_sel()

func _on_undo_draw():
	if game.undo_last_draw():
		_clear_sel()

func _on_hand_click(data: Dictionary):
	var found = -1
	for i in sel_hand.size():
		if sel_hand[i].id == data.id: found = i; break
	if found != -1: sel_hand.remove_at(found)
	else: sel_hand.append(data)
	_refresh()

func _clear_sel():
	sel_hand.clear(); sel_discard = -1; _refresh()

func _on_play():
	var unc = null
	for c in sel_hand:
		if c.isJoker and (not c.has("jokerAssumedRank") or not c.has("jokerAssumedSuit")):
			unc = c; break
	if unc:
		var opts = game.get_valid_joker_assignments(sel_hand)
		if opts.size() == 0:
			game.message = "Ошибка: невозможно использовать джокера в этой комбинации."
			game.state_changed.emit()
		elif opts.size() == 1:
			_on_full_auto_joker(unc, opts[0], "PLAY", "")
		else:
			pend_type = "PLAY"; pend_joker = unc; _show_joker_opts(opts)
	else:
		if game.net_play_meld(sel_hand): _clear_sel()

func _on_discard():
	if sel_hand.size() == 1:
		if game.net_discard(sel_hand[0].id): _clear_sel()

func _on_sort():
	game.toggle_sort_mode()

func _on_table_click(meld_id: String, card: Dictionary):
	if card.isJoker and sel_hand.size() == 1:
		if game.net_swap_joker(meld_id, card.id, sel_hand[0].id): _clear_sel()
	elif sel_hand.size() == 1:
		var sc = sel_hand[0]
		if sc.isJoker and (not sc.has("jokerAssumedRank") or not sc.has("jokerAssumedSuit")):
			var opts = game.get_valid_joker_assignments([sc], meld_id)
			if opts.size() == 0:
				game.message = "Ошибка: джокер не подходит к этой комбинации."
				game.state_changed.emit()
			elif opts.size() == 1:
				_on_full_auto_joker(sc, opts[0], "ADD", meld_id)
			else:
				pend_type = "ADD"; pend_joker = sc; pend_meld = meld_id; _show_joker_opts(opts)
		else:
			if game.net_add_to_meld(meld_id, sc): _clear_sel()

func _show_joker_opts(opts: Array):
	_clear(joker_opts_container)
	for o in opts:
		var is_red = o.suit in ["♥", "♦"]
		var btn_col = Color("#991b1b") if is_red else Color("#1e3a5f")
		var b = _mk_btn(o.rank + o.suit, btn_col, 68, 54, 12, 22)
		b.add_theme_color_override("font_color", Color("#fecaca") if is_red else Color("#bfdbfe"))
		var st = o.suit; var rk = o.rank
		b.pressed.connect(func(): _on_joker_choice(st, rk))
		joker_opts_container.add_child(b)
	joker_panel.show()
	joker_panel.move_to_front()

func _on_joker_choice(suit: String, rank: String):
	pend_joker["jokerAssumedSuit"] = suit
	pend_joker["jokerAssumedRank"] = rank
	joker_panel.hide()
	var saved_joker = pend_joker
	var saved_type = pend_type
	var saved_meld = pend_meld
	pend_type = ""; pend_joker = {}; pend_meld = ""
	if saved_type == "PLAY":
		if not game.net_play_meld(sel_hand):
			saved_joker.erase("jokerAssumedSuit"); saved_joker.erase("jokerAssumedRank")
		else: 
			_clear_sel()
	elif saved_type == "ADD":
		if not game.net_add_to_meld(saved_meld, saved_joker):
			saved_joker.erase("jokerAssumedSuit"); saved_joker.erase("jokerAssumedRank")
		else: 
			_clear_sel()

func _on_full_auto_joker(joker: Dictionary, opt: Dictionary, p_type: String, m_id: String):
	joker["jokerAssumedSuit"] = opt.suit
	joker["jokerAssumedRank"] = opt.rank
	if p_type == "PLAY":
		if not game.net_play_meld(sel_hand):
			joker.erase("jokerAssumedSuit"); joker.erase("jokerAssumedRank")
		else: _clear_sel()
	else:
		if not game.net_add_to_meld(m_id, joker):
			joker.erase("jokerAssumedSuit"); joker.erase("jokerAssumedRank")
		else: _clear_sel()

func _on_continue():
	if game.phase == "ROUND_OVER": game.start_round()
	else:
		lobby_panel.show(); round_panel.hide()
		lobby_panel.move_to_front()

func _on_multiplayer_game_ready():
	multiplayer_panel.hide()
	# Start multiplayer game
	var peer_names = NetworkManager.peer_names.duplicate()
	game.start_game_multiplayer(peer_names)

func _on_connection_failed(reason: String):
	msg_lbl.text = "Ошибка сети: " + reason
	multiplayer_refs["action_btn"].disabled = false

func _on_host_disconnected():
	msg_lbl.text = "Хост отключился"
	multiplayer_panel.hide()
	mode_panel.show()

func _on_start_game_pressed():
	if NetworkManager.is_host:
		NetworkManager.start_game_broadcast()
		_on_multiplayer_game_ready()
