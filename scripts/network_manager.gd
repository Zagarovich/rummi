extends Node

## NetworkManager — авторитарный LAN-мультиплеер на ENet
## Хост владеет GameService. Клиенты присылают RPC-действия, получают broadcast состояния.

const DEFAULT_PORT := 7344
const MAX_PLAYERS := 4

signal player_list_changed(players: Dictionary)   # id -> name
signal server_started()
signal joined_room()
signal connection_failed(reason: String)
signal host_disconnected()
signal game_ready()   # сервер нажал "Начать игру"

var peer_names: Dictionary = {}   # peer_id -> display_name
var my_name: String = "Игрок"
var is_host: bool = false
var _peer: ENetMultiplayerPeer = null

# ═══ Хост ════════════════════════════════════════════════════════════════════
func host_game(player_name: String) -> Error:
	my_name = player_name
	_peer = ENetMultiplayerPeer.new()
	var err = _peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	if err != OK:
		connection_failed.emit("Не удалось открыть порт %d. Ошибка: %d" % [DEFAULT_PORT, err])
		return err

	multiplayer.multiplayer_peer = _peer
	is_host = true
	peer_names[1] = my_name   # id=1 всегда хост

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	print("[NET] Хост запущен на порту ", DEFAULT_PORT)
	server_started.emit()
	player_list_changed.emit(peer_names.duplicate())
	return OK

# ═══ Клиент ══════════════════════════════════════════════════════════════════
func join_game(ip: String, player_name: String) -> Error:
	my_name = player_name
	_peer = ENetMultiplayerPeer.new()
	var err = _peer.create_client(ip, DEFAULT_PORT)
	if err != OK:
		connection_failed.emit("Не удалось подключиться к %s:%d" % [ip, DEFAULT_PORT])
		return err

	multiplayer.multiplayer_peer = _peer
	is_host = false
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[NET] Подключение к ", ip, ":", DEFAULT_PORT)
	return OK

func disconnect_all():
	if _peer:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	peer_names.clear()
	is_host = false

func get_player_count() -> int:
	return peer_names.size()

func get_my_id() -> int:
	return multiplayer.get_unique_id()

func get_peer_ids() -> Array:
	return peer_names.keys()

# ═══ Callbacks ════════════════════════════════════════════════════════════════
func _on_peer_connected(id: int):
	print("[NET] Подключился peer id=", id)
	# Хост шлет новому пиру список уже подключенных
	if is_host:
		rpc_id(id, "_receive_name_list", peer_names)

func _on_peer_disconnected(id: int):
	print("[NET] Отключился peer id=", id)
	peer_names.erase(id)
	player_list_changed.emit(peer_names.duplicate())
	if not is_host and id == 1:
		host_disconnected.emit()

func _on_connected_to_server():
	print("[NET] Соединение с сервером установлено. My id=", multiplayer.get_unique_id())
	# Сообщаем своё имя серверу
	rpc_id(1, "_register_name", multiplayer.get_unique_id(), my_name)
	joined_room.emit()

func _on_connection_failed():
	connection_failed.emit("Сервер недоступен. Проверьте IP-адрес.")

func _on_server_disconnected():
	host_disconnected.emit()

# ═══ RPC ─────────────────────────────────────────────────────────────────────
## Клиент → Хост: зарегистрировать имя
@rpc("any_peer", "call_remote", "reliable")
func _register_name(peer_id: int, p_name: String):
	if not is_host: return
	peer_names[peer_id] = p_name
	print("[NET] Зарегистрирован: id=%d name=%s" % [peer_id, p_name])
	# Брадкастим обновленный список всем
	rpc("_receive_name_list", peer_names)
	player_list_changed.emit(peer_names.duplicate())

## Хост → Все: принять обновленный список игроков
@rpc("authority", "call_local", "reliable")
func _receive_name_list(names: Dictionary):
	peer_names = names.duplicate()
	print("[NET] Список игроков: ", peer_names)
	player_list_changed.emit(peer_names.duplicate())

## Хост → Все: запуск игры
@rpc("authority", "call_local", "reliable")
func _notify_game_start():
	print("[NET] Игра начинается!")
	game_ready.emit()

## Хост стартует игру (может вызвать только хост из UI)
func start_game_broadcast():
	if not is_host: return
	rpc("_notify_game_start")
