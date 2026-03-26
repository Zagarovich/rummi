extends Node
class_name GameService

signal state_changed

var suits = ["♠", "♥", "♦", "♣"]
var ranks = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "В", "Д", "К", "Т"]

var players = []
var current_player_index = 0
var deck = []
var discard_pile = []  # Пул (открытые карты). Индекс 0 — верхняя (последняя сброшенная) карта, индекс size()-1 — нижняя.
var melds = []
var phase = "DRAW"
var target_score = 500
var round_number = 1
var message = "Начало игры. Игрок 1 берет карту."
var must_play_card_id = null
var hand_sort_mode = "SUIT"
var num_bots_setting = 1
var last_draw_snapshot = {}

# ─── Multiplayer helpers ────────────────────────────────────────────────────
## Возвращает true, если это серверная копия (или одиночная игра)
func _is_server() -> bool:
	return (multiplayer.multiplayer_peer == null) or multiplayer.is_server()

## Стартует одиночную (офлайн) игру
func start_game(num_bots: int = 1):
	num_bots_setting = num_bots
	players = [{"id": 1, "name": "Вы", "hand": [], "isOpened": false, "globalScore": 0, "isBot": false, "peer_id": 1}]
	for i in range(1, num_bots + 1):
		players.append({"id": i + 1, "name": "Бот " + str(i), "hand": [], "isOpened": false, "globalScore": 0, "isBot": true, "peer_id": -1})
	round_number = 1
	start_round()

## Стартует сетевую игру; вызывается только хостом
func start_game_multiplayer(peer_names: Dictionary):
	players = []
	var pid = 1
	for peer_id in peer_names.keys():
		players.append({
			"id": pid,
			"name": peer_names[peer_id],
			"hand": [],
			"isOpened": false,
			"globalScore": 0,
			"isBot": false,
			"peer_id": peer_id
		})
		pid += 1
	round_number = 1
	start_round()

# ─── State Broadcast ─────────────────────────────────────────────────────────
## Сериализует и рассылает состояние всем клиентам (хост-авторитарно)
func _broadcast_state():
	if not _is_server(): return
	var data = _serialize_state()
	rpc("_receive_state", data)

## Сериализует полное состояние (руки скрыты для чужих)
func _serialize_state() -> Dictionary:
	var my_peer_id = 1
	if multiplayer.multiplayer_peer != null:
		my_peer_id = multiplayer.get_unique_id()
		
	var players_data = []
	for p in players:
		var pd = p.duplicate(true)
		# Скрываем карты чужих игроков (заменяем на пустые рубашки)
		if p.get("peer_id", -1) != my_peer_id and not p.get("isBot", false):
			pd["hand"] = []  # Клиент не увидит чужие карты
		players_data.append(pd)
		
	var dict = {}
	dict["players"] = players_data
	dict["current_player_index"] = current_player_index
	dict["discard_pile"] = discard_pile
	dict["melds"] = melds
	dict["phase"] = phase
	dict["round_number"] = round_number
	dict["message"] = message
	dict["must_play_card_id"] = must_play_card_id
	dict["deck_size"] = deck.size()
	return dict

## Принимает полное состояние от хоста
@rpc("authority", "call_local", "reliable")
func _receive_state(data: Dictionary):
	players = data["players"]
	current_player_index = data["current_player_index"]
	discard_pile = data["discard_pile"]
	melds = data["melds"]
	phase = data["phase"]
	round_number = data["round_number"]
	message = data["message"]
	
	if data.has("must_play_card_id"):
		must_play_card_id = data["must_play_card_id"]
	else:
		must_play_card_id = null
		
	if not _is_server():
		state_changed.emit()

# ─── RPC Action Wrappers ──────────────────────────────────────────────────────
## Клиент вызывает эти методы — они пересылают действие хосту

@rpc("any_peer", "call_remote", "reliable")
func _rpc_draw_deck():
	if not _is_server(): return
	draw_from_deck()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_draw_discard(index: int):
	if not _is_server(): return
	draw_from_discard(index)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_discard(card_id: String):
	if not _is_server(): return
	discard_card(card_id)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_play_meld(card_ids: Array, p_type: String):
	if not _is_server(): return
	var cards = _find_cards_by_ids(card_ids)
	if p_type == "":
		play_meld(cards, null)
	else:
		play_meld(cards, p_type)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_add_to_meld(meld_id: String, card_id: String):
	if not _is_server(): return
	var card = _find_card_by_id(card_id)
	if card: add_to_meld(meld_id, card)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_swap_joker(meld_id: String, joker_id: String, replacement_id: String):
	if not _is_server(): return
	swap_joker(meld_id, joker_id, replacement_id)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_current_player_index(_new_index: int):
	if not _is_server(): return
	_set_current_player_by_peer(multiplayer.get_remote_sender_id())

## Позволяет серверу переопределить текущий ход по peer_id
func _set_current_player_by_peer(peer_id: int):
	for i in range(players.size()):
		if players[i].get("peer_id", -1) == peer_id:
			# Валидация: только текущий игрок может делать ход
			if current_player_index == i:
				return  # всё ок, игрок правильный
	push_warning("[NET] Попытка хода не в свой ход от peer " + str(peer_id))

## Helper: найти карты по списку id
func _find_cards_by_ids(ids: Array) -> Array:
	var result = []
	var cp = get_current_player()
	for id in ids:
		for c in cp.hand:
			if c.id == id:
				result.append(c)
				break
	return result

func _find_card_by_id(id: String) -> Dictionary:
	var cp = get_current_player()
	for c in cp.hand:
		if c.id == id: return c
	return {}

## Универсальная точка входа для действий (работает в одиночном и сетевом режиме)
## Используется из main.gd вместо прямого вызова методов
func net_draw_deck():
	if _is_server(): draw_from_deck()
	else: rpc_id(1, "_rpc_draw_deck")

func net_draw_discard(index: int):
	if _is_server(): draw_from_discard(index)
	else: rpc_id(1, "_rpc_draw_discard", index)

func net_discard(card_id: String):
	if _is_server(): discard_card(card_id)
	else: rpc_id(1, "_rpc_discard", card_id)

func net_play_meld(cards: Array, p_type: Variant = null) -> bool:
	if _is_server():
		return play_meld(cards, p_type)
	else:
		var ids = []
		for c in cards:
			ids.append(c.id)
		var t_str = ""
		if p_type != null:
			t_str = str(p_type)
		rpc_id(1, "_rpc_play_meld", ids, t_str)
		return true

func net_add_to_meld(meld_id: String, card: Dictionary) -> bool:
	if _is_server():
		return add_to_meld(meld_id, card)
	else:
		rpc_id(1, "_rpc_add_to_meld", meld_id, card.id)
		return true

func net_swap_joker(meld_id: String, joker_id: String, rep_id: String) -> bool:
	if _is_server():
		return swap_joker(meld_id, joker_id, rep_id)
	else:
		rpc_id(1, "_rpc_swap_joker", meld_id, joker_id, rep_id)
		return true



func start_round():
	deck = create_deck()
	
	for p in players:
		p.hand = []
		for i in range(7): p.hand.append(deck.pop_front())
		p.hand = sort_hand(p.hand)
		p.isOpened = false
	
	var top_card = deck.pop_front()
	if top_card:
		discard_pile = [top_card]
	else:
		discard_pile = []
		
	melds = []
	current_player_index = 0
	phase = "DRAW"
	must_play_card_id = null
	last_draw_snapshot = {}
	message = "Раунд %d. Ход %s. Возьмите карту." % [round_number, get_current_player().name]
	state_changed.emit()

func create_deck():
	var new_deck = []
	var id_counter = 0
	for suit in suits:
		for rank in ranks:
			new_deck.append({
				"id": "c_" + str(id_counter),
				"suit": suit,
				"rank": rank,
				"isJoker": false
			})
			id_counter += 1
			
	new_deck.append({"id": "c_" + str(id_counter), "isJoker": true})
	id_counter += 1
	new_deck.append({"id": "c_" + str(id_counter), "isJoker": true})
	
	new_deck.shuffle()
	return new_deck

func get_current_player():
	if players.is_empty():
		return {"id": 0, "name": "", "hand": [], "isOpened": false, "globalScore": 0}
	return players[current_player_index]

func toggle_sort_mode():
	hand_sort_mode = "RANK" if hand_sort_mode == "SUIT" else "SUIT"
	for p in players:
		p.hand = sort_hand(p.hand)
	state_changed.emit()

func sort_hand(hand: Array):
	var suit_order = {"♠": 1, "♥": 2, "♣": 3, "♦": 4}
	var rank_order = {"2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9, "10": 10, "В": 11, "Д": 12, "К": 13, "Т": 14}
	
	var sorted = hand.duplicate()
	sorted.sort_custom(func(a, b):
		if a.isJoker and not b.isJoker: return false
		if b.isJoker and not a.isJoker: return true
		if a.isJoker and b.isJoker: return true
		
		if hand_sort_mode == "SUIT":
			if suit_order[a.suit] != suit_order[b.suit]:
				return suit_order[a.suit] < suit_order[b.suit]
			return rank_order[a.rank] < rank_order[b.rank]
		else:
			if rank_order[a.rank] != rank_order[b.rank]:
				return rank_order[a.rank] < rank_order[b.rank]
			return suit_order[a.suit] < suit_order[b.suit]
	)
	return sorted

func sort_run(cards: Array):
	var sorted = cards.duplicate()
	sorted.sort_custom(func(a, b):
		var rA = a.jokerAssumedRank if a.isJoker else a.rank
		var rB = b.jokerAssumedRank if b.isJoker else b.rank
		return ranks.find(rA) < ranks.find(rB)
	)
	
	var gap_index = -1
	for i in range(sorted.size() - 1):
		var rA = sorted[i].jokerAssumedRank if sorted[i].isJoker else sorted[i].rank
		var rB = sorted[i+1].jokerAssumedRank if sorted[i+1].isJoker else sorted[i+1].rank
		if ranks.find(rB) - ranks.find(rA) > 1:
			gap_index = i
			break
			
	if gap_index != -1:
		var wrapped = []
		wrapped.append_array(sorted.slice(gap_index + 1, sorted.size()))
		wrapped.append_array(sorted.slice(0, gap_index + 1))
		return wrapped
	return sorted

func draw_from_deck():
	if phase != "DRAW": return
	_capture_draw_snapshot()
	
	if deck.is_empty():
		if discard_pile.size() > 1:
			var top_card = discard_pile.pop_front()
			deck = discard_pile.duplicate()
			deck.shuffle()
			discard_pile = [top_card]
			message = "Резерв пуст! В пул перемешаны сброшенные карты. Возьмите карту."
			state_changed.emit()
		else:
			message = "Колода пуста! Пул пуст тоже. Ничья. Новый раунд."
			state_changed.emit()
			get_tree().create_timer(3.0).timeout.connect(start_round, CONNECT_ONE_SHOT)
			return
		
	var card = deck.pop_front()
	var cp = get_current_player()
	card["isNewDrawn"] = true
	cp.hand.append(card)
	cp.hand = sort_hand(cp.hand)
	
	phase = "ACTION"
	message = "Вы можете выложить комбинации или сбросить карту для завершения хода."
	state_changed.emit()

func draw_from_discard(index: int):
	if phase != "DRAW": return
	if index < 0 or index >= discard_pile.size(): return
	if not can_draw_from_discard(index):
		message = "Нельзя взять из пула: целевая карта не собирает комбинацию с рукой (включая джокеры)."
		state_changed.emit()
		return
	_capture_draw_snapshot()
	
	var taken_cards = []
	for i in range(index + 1):
		taken_cards.append(discard_pile.pop_front())
		
	var target_card = taken_cards.back()
	must_play_card_id = target_card.id
	
	var cp = get_current_player()
	cp.hand.append_array(taken_cards)
	cp.hand = sort_hand(cp.hand)
	
	phase = "ACTION"
	message = "Вы взяли карты из пула. Вы ОБЯЗАНЫ использовать целевую карту в комбинации в этот ход."
	state_changed.emit()

func can_draw_from_discard(index: int) -> bool:
	if phase != "DRAW": return false
	if index < 0 or index >= discard_pile.size(): return false
	var taken_cards = discard_pile.slice(0, index + 1)
	var target = taken_cards[taken_cards.size() - 1]
	var available = get_current_player().hand.duplicate(true)
	available.append_array(taken_cards)
	# Проверяем, можно ли использовать целевую карту в новой комбинации
	if _has_potential_meld_with_target(available, target.id):
		return true
	# Или можно добавить её к существующему мелду
	return can_add_to_existing_meld(target)

func discard_card(card_id: String) -> bool:
	if phase != "ACTION" and phase != "DISCARD": return false
	
	if must_play_card_id != null:
		if get_current_player().get("isBot", false):
			# Failsafe для бота: если не вышло собрать, сбрасываем флаг, чтобы не завис
			must_play_card_id = null
		else:
			message = "Ошибка: Вы обязаны выложить целевую карту из пула в комбинацию перед сбросом!"
			state_changed.emit()
			return false
		
	var cp = get_current_player()
	var discarded_card = null
	var c_index = -1
	for i in range(cp.hand.size()):
		if cp.hand[i].id == card_id:
			c_index = i
			break
			
	if c_index != -1:
		last_draw_snapshot = {}
		discarded_card = cp.hand[c_index]
		cp.hand.remove_at(c_index)
		
		# Reset joker assumptions when discarded
		if discarded_card.isJoker:
			discarded_card.erase("jokerAssumedRank")
			discarded_card.erase("jokerAssumedSuit")
			
		discard_pile.push_front(discarded_card)
		
		if cp.hand.is_empty():
			end_round()
		else:
			next_turn()
		return true
	return false

func next_turn():
	var cp = get_current_player()
	for c in cp.hand: c.erase("isNewDrawn")
	
	current_player_index = (current_player_index + 1) % players.size()
	phase = "DRAW"
	must_play_card_id = null
	last_draw_snapshot = {}
	message = "Ход %s. Возьмите карту." % get_current_player().name
	state_changed.emit()
	
	if get_current_player().get("isBot", false):
		get_tree().create_timer(1.0).timeout.connect(_ai_draw, CONNECT_ONE_SHOT)

func _ai_draw():
	if phase != "DRAW" or not get_current_player().get("isBot", false): return
	
	# Ищем самую глубокую карту в пуле, которая нам полезна
	var best_index = -1
	for i in range(discard_pile.size() - 1, -1, -1):
		if _ai_should_take_pool(discard_pile[i]):
			best_index = i
			break
			
	if best_index != -1:
		draw_from_discard(best_index)
	else:
		draw_from_deck()
	get_tree().create_timer(1.2).timeout.connect(_ai_act, CONNECT_ONE_SHOT)

func _ai_should_take_pool(target: Dictionary) -> bool:
	var cp = get_current_player()
	if target.isJoker: return true # Джокер берем всегда
	
	# Проверка возможности добавления к существующим мелдам
	if can_add_to_existing_meld(target):
		return true
	
	# СЕТ
	var same_rank = 0
	var jokers = 0
	for c in cp.hand:
		if c.isJoker: jokers += 1
		elif c.has("rank") and c.rank == target.rank: same_rank += 1
	if same_rank >= 2 or (same_rank == 1 and jokers >= 1): return true
	
	# СЕРИЯ
	var suit_cards = []
	for c in cp.hand:
		if not c.isJoker and c.has("suit") and c.suit == target.suit: suit_cards.append(c)
	var rank_order = {"2":2,"3":3,"4":4,"5":5,"6":6,"7":7,"8":8,"9":9,"10":10,"В":11,"Д":12,"К":13,"Т":14}
	var tv = rank_order.get(target.rank, 0)
	
	# Проверка возможности создания серии из 3+ карт
	if suit_cards.size() >= 2:
		# Создаем массив всех рангов (включая целевую карту)
		var all_ranks = [tv]
		for c in suit_cards:
			all_ranks.append(rank_order.get(c.rank, 0))
		all_ranks.sort()
		
		# Проверяем последовательные комбинации
		for i in range(all_ranks.size()):
			for j in range(i + 1, all_ranks.size()):
				var diff = all_ranks[j] - all_ranks[i]
				if diff <= 2:  # Разрыв не более 1 (или 2 с джокером)
					# Если у нас есть джокер или карты для заполнения пробела
					if jokers >= 1 or (diff == 1 and j - i >= 2):
						return true
	
	# Проверка с использованием джокеров
	if jokers >= 1 and suit_cards.size() >= 1:
		# Джокер может помочь создать серию с любой картой
		return true
			
	return false

func _ai_act():
	if phase != "ACTION" or not get_current_player().get("isBot", false): return
	_ai_try_melds()
	get_tree().create_timer(0.8).timeout.connect(_ai_discard, CONNECT_ONE_SHOT)

func _ai_try_melds():
	var cp = get_current_player()
	var rank_order = {"2":2,"3":3,"4":4,"5":5,"6":6,"7":7,"8":8,"9":9,"10":10,"В":11,"Д":12,"К":13,"Т":14}
	
	# Если есть обязательная карта из пула, пытаемся использовать её в первую очередь
	if must_play_card_id != null:
		var target_card = null
		for c in cp.hand:
			if c.id == must_play_card_id:
				target_card = c
				break
		if target_card:
			# Пробуем добавить к существующему мелду
			for m in melds:
				if add_to_meld(m.id, target_card):
					return
			# Пробуем создать новую комбинацию с этой картой
			# Группа (сет)
			var same_rank_cards = []
			var jokers = 0
			for c in cp.hand:
				if c.isJoker:
					jokers += 1
				elif c.rank == target_card.rank:
					same_rank_cards.append(c)
			# Нужно хотя бы 2 карты того же ранга (или 1 + джокер)
			if same_rank_cards.size() >= 2 or (same_rank_cards.size() >= 1 and jokers >= 1):
				var attempt = []
				attempt.append(target_card)
				for c in same_rank_cards:
					if c.id != target_card.id:
						attempt.append(c)
						if attempt.size() >= 3: break
				# Добавляем джокеры при необходимости
				if attempt.size() < 3 and jokers > 0:
					for c in cp.hand:
						if c.isJoker and not c.has("jokerAssumedRank"):
							attempt.append(c)
							if attempt.size() >= 3: break
				if attempt.size() >= 3 and is_valid_group(attempt) and is_unique_on_table(attempt):
					play_meld(attempt, "GROUP")
					_ai_try_melds()
					return
			# Серия (секв)
			var same_suit_cards = []
			for c in cp.hand:
				if not c.isJoker and c.suit == target_card.suit:
					same_suit_cards.append(c)
			if same_suit_cards.size() >= 2:
				var all_cards = same_suit_cards.duplicate()
				all_cards.append(target_card)
				all_cards.sort_custom(func(a,b): return rank_order[a.rank] < rank_order[b.rank])
				# Ищем непрерывную подпоследовательность длиной >=3, содержащую target_card
				for start in range(all_cards.size()):
					for end in range(start + 2, all_cards.size() + 1):
						var slice = all_cards.slice(start, end)
						var contains_target = false
						for sc in slice:
							if sc.id == target_card.id:
								contains_target = true
								break
						if contains_target and cp.hand.size() - slice.size() >= 1 and is_valid_run(slice):
							play_meld(slice, "RUN")
							_ai_try_melds()
							return
	
	# Попытка доложить карты к существующим мелдам
	var added_something = true
	while added_something and cp.hand.size() > 1:
		added_something = false
		for m in melds:
			for i in range(cp.hand.size() - 1, -1, -1): # итерируемся с конца
				var c = cp.hand[i]
				if c.isJoker:
					var opts = get_valid_joker_assignments([c], m.id)
					if opts.size() > 0:
						c["jokerAssumedSuit"] = opts[0].suit
						c["jokerAssumedRank"] = opts[0].rank
						if add_to_meld(m.id, c):
							added_something = true
							break
						else:
							c.erase("jokerAssumedSuit")
							c.erase("jokerAssumedRank")
				else:
					if add_to_meld(m.id, c):
						added_something = true
						break
			if added_something: break

	# Попытка выкупить джокера с поля
	for m in melds:
		for joker in m.cards:
			if joker.isJoker and joker.has("jokerAssumedRank") and joker.has("jokerAssumedSuit"):
				# Ищем карту в руке для замены
				for c in cp.hand:
					if c.isJoker: continue
					if m.type == "RUN":
						if c.suit == joker.jokerAssumedSuit and c.rank == joker.jokerAssumedRank:
							if swap_joker(m.id, joker.id, c.id):
								_ai_try_melds()
								return
					else: # GROUP
						if c.rank == joker.jokerAssumedRank:
							# Проверяем, что масти нет в других картах мелда
							var suit_exists = false
							for oc in m.cards:
								if oc.id != joker.id and not oc.isJoker and oc.suit == c.suit:
									suit_exists = true
									break
							if not suit_exists:
								if swap_joker(m.id, joker.id, c.id):
									_ai_try_melds()
									return

	if cp.hand.size() <= 1: return
	
	# Попытка найти группу (3 карты одного номинала)
	var by_rank = {}
	for c in cp.hand:
		if c.isJoker: continue
		if not by_rank.has(c.rank): by_rank[c.rank] = []
		by_rank[c.rank].append(c)
	
	for rank in by_rank:
		var grp = by_rank[rank]
		if grp.size() >= 3 and cp.hand.size() - 3 >= 1:
			var attempt = grp.slice(0, 3)
			if is_valid_group(attempt) and is_unique_on_table(attempt):
				play_meld(attempt, "GROUP")
				_ai_try_melds()
				return
	
	# Попытка найти серию (3+ карты одной масти по порядку)
	var by_suit = {}
	for c in cp.hand:
		if c.isJoker: continue
		if not by_suit.has(c.suit): by_suit[c.suit] = []
		by_suit[c.suit].append(c)
	
	for suit in by_suit:
		var slist = by_suit[suit]
		slist.sort_custom(func(a,b): return rank_order[a.rank] < rank_order[b.rank])
		for start in range(slist.size()):
			for end in range(start + 2, slist.size() + 1):
				var slice = slist.slice(start, end)
				if cp.hand.size() - slice.size() >= 1 and is_valid_run(slice):
					play_meld(slice, "RUN")
					_ai_try_melds()
					return

func _ai_discard():
	if not phase in ["ACTION", "DISCARD"]: return
	if not get_current_player().get("isBot", false): return
	var cp = get_current_player()
	if cp.hand.is_empty(): return
	# Сбрасываем самую дорогую карту (не джокер)
	var worst = cp.hand[0]
	for c in cp.hand:
		if not c.isJoker and get_card_value(c, true) >= get_card_value(worst, true):
			worst = c
	discard_card(worst.id)

func is_valid_group(cards: Array) -> bool:
	if cards.size() < 3 or cards.size() > 4: return false
	var rank = null
	var used_suits = []
	
	for c in cards:
		var c_rank = c.get("jokerAssumedRank") if c.isJoker else c.get("rank")
		var c_suit = c.get("jokerAssumedSuit") if c.isJoker else c.get("suit")
		
		if c_rank == null or c_suit == null: return false
		
		if rank == null: rank = c_rank
		elif rank != c_rank: return false
		
		if c_suit in used_suits: return false
		used_suits.append(c_suit)
		
	return true

## Проверяет, является ли набор карт валидной секвенцией (RUN).
## Поддерживает обычные последовательности (например, 5♣ 6♣ 7♣) и круговые (например, Д♠ К♠ Т♠ 2♠ 3♠).
## Джокеры учитываются через jokerAssumedRank/jokerAssumedSuit.
func is_valid_run(cards: Array) -> bool:
	if cards.size() < 3 or cards.size() > 13: return false
	var suit = null
	var card_ranks = []
	
	for c in cards:
		var c_suit = c.get("jokerAssumedSuit") if c.isJoker else c.get("suit")
		var c_rank = c.get("jokerAssumedRank") if c.isJoker else c.get("rank")
		
		if c_suit == null or c_rank == null: return false
		if suit == null: suit = c_suit
		elif suit != c_suit: return false
		
		card_ranks.append(c_rank)
		
	var rank_indices = []
	for cr in card_ranks:
		rank_indices.append(ranks.find(cr))
	rank_indices.sort()
	
	var unique_indices = []
	for r in rank_indices:
		if not r in unique_indices: unique_indices.append(r)
	if unique_indices.size() != rank_indices.size(): return false
	
	var is_normal = true
	for i in range(1, rank_indices.size()):
		if rank_indices[i] != rank_indices[i-1] + 1:
			is_normal = false
			break
	if is_normal: return true

	var gaps = 0
	for i in range(1, rank_indices.size()):
		var diff = rank_indices[i] - rank_indices[i-1]
		if diff > 1:
			gaps += 1
			if diff != 13 - rank_indices.size() + 1: return false

	var wrap_diff = (rank_indices[0] + 13) - rank_indices[rank_indices.size() - 1]
	if wrap_diff > 1: gaps += 1

	return gaps == 1

func is_unique_on_table(cards: Array) -> bool:
	var all_table_cards = []
	for m in melds:
		all_table_cards.append_array(m.cards)
		
	for c in cards:
		var c_suit = c.get("jokerAssumedSuit") if c.isJoker else c.get("suit")
		var c_rank = c.get("jokerAssumedRank") if c.isJoker else c.get("rank")
		
		for tc in all_table_cards:
			var tc_suit = tc.get("jokerAssumedSuit") if tc.isJoker else tc.get("suit")
			var tc_rank = tc.get("jokerAssumedRank") if tc.isJoker else tc.get("rank")
			if tc_suit == c_suit and tc_rank == c_rank:
				return false
	return true

func can_add_to_existing_meld(card: Dictionary) -> bool:
	for m in melds:
		var test_cards = m.cards.duplicate(true)
		var test_card = card.duplicate(true)
		test_cards.append(test_card)
		
		if m.type == "GROUP" and is_valid_group(test_cards):
			return true
		elif m.type == "RUN" and is_valid_run(test_cards):
			return true
	return false

func play_meld(cards: Array, type = null) -> bool:
	if phase != "ACTION": return false
	
	var determined_type = type
	if determined_type == null:
		if is_valid_group(cards): determined_type = "GROUP"
		elif is_valid_run(cards): determined_type = "RUN"
		else:
			message = "Ошибка: Неверная комбинация!"
			state_changed.emit()
			return false
			
	var cp = get_current_player()
				
	if cp.hand.size() - cards.size() == 0:
		message = "Ошибка: У вас должна остаться минимум 1 карта для сброса!"
		state_changed.emit()
		return false
		
	if not is_unique_on_table(cards):
		message = "Ошибка: Одна или несколько карт уже присутствуют на столе!"
		state_changed.emit()
		return false

	if must_play_card_id != null:
		var contains_must_play = false
		for c in cards:
			if c.id == must_play_card_id:
				contains_must_play = true
				break
		if contains_must_play:
			must_play_card_id = null
			
	var to_remove = []
	for c in cards: to_remove.append(c.id)
	
	var new_hand = []
	for c in cp.hand:
		if not c.id in to_remove:
			new_hand.append(c)
	cp.hand = new_hand
	cp.isOpened = true
	
	var final_cards = cards.duplicate()
	if determined_type == "RUN":
		final_cards = sort_run(final_cards)
		
	for c in final_cards:
		c["ownerId"] = cp.id
		
	melds.append({
		"id": "m_" + str(Time.get_ticks_msec()) + "_" + str(randi()),
		"type": determined_type,
		"cards": final_cards,
		"ownerId": cp.id
	})
	
	message = "Комбинация выложена."
	last_draw_snapshot = {}
	state_changed.emit()
	return true

func add_to_meld(meld_id: String, card: Dictionary) -> bool:
	if phase != "ACTION": return false
	
	var cp = get_current_player()
	
	if not cp.isOpened:
		message = "Ошибка: Сначала выложите свою первую комбинацию (Открытие)!"
		state_changed.emit()
		return false
		
	if cp.hand.size() - 1 == 0:
		message = "Ошибка: Нужна 1 карта для сброса!"
		state_changed.emit()
		return false
		
	if not is_unique_on_table([card]):
		message = "Ошибка: Эта карта уже есть на столе!"
		state_changed.emit()
		return false

	var success = false
	for i in range(melds.size()):
		if melds[i].id == meld_id:
			var test_cards = melds[i].cards.duplicate()
			var test_card = card.duplicate()
			test_card["ownerId"] = cp.id
			test_cards.append(test_card)
			
			if melds[i].type == "GROUP" and is_valid_group(test_cards):
				melds[i].cards = test_cards
				success = true
			elif melds[i].type == "RUN" and is_valid_run(test_cards):
				melds[i].cards = sort_run(test_cards)
				success = true
			break
			
	if success:
		if must_play_card_id == card.id:
			must_play_card_id = null
		
		var new_hand = []
		for c in cp.hand:
			if c.id != card.id:
				new_hand.append(c)
		cp.hand = new_hand
		
		message = "Карта добавлена."
		last_draw_snapshot = {}
		state_changed.emit()
		return true
	
	message = "Ошибка: Карта не подходит."
	state_changed.emit()
	return false

func swap_joker(meld_id: String, joker_id: String, replacement_card_id: String) -> bool:
	if phase != "ACTION":
		message = "Ошибка: Выкупить Джокера можно только в фазе действия."
		state_changed.emit()
		return false
		
	var success = false
	var extracted_joker = null
	var cp = get_current_player()
	var replacement_card = null
	
	for c in cp.hand:
		if c.id == replacement_card_id:
			replacement_card = c
			break
			
	if replacement_card == null: return false
	
	# Нельзя выкупить джокера, если это единственная карта в руке – после обмена не останется карт для сброса
	if cp.hand.size() == 1:
		message = "Нельзя выкупить джокера, если это ваша единственная карта!"
		state_changed.emit()
		return false
	
	for i in range(melds.size()):
		if melds[i].id == meld_id:
			for j in range(melds[i].cards.size()):
				var c = melds[i].cards[j]
				if c.id == joker_id and c.isJoker:
					var can_swap = false
					if melds[i].type == "RUN":
						can_swap = (replacement_card.suit == c.jokerAssumedSuit and replacement_card.rank == c.jokerAssumedRank)
					else: # GROUP
						if replacement_card.rank == c.jokerAssumedRank:
							var other_suits = []
							for cardi in melds[i].cards:
								if cardi.id != c.id: 
									other_suits.append(cardi.get("suit", ""))
							can_swap = not replacement_card.suit in other_suits
					
					if can_swap:
						extracted_joker = c.duplicate()
						extracted_joker.erase("jokerAssumedRank")
						extracted_joker.erase("jokerAssumedSuit")
						extracted_joker.erase("ownerId")
						
						var new_rep = replacement_card.duplicate()
						new_rep["ownerId"] = cp.id
						new_rep["isSwapped"] = true
						melds[i].cards[j] = new_rep
						
						if melds[i].type == "RUN":
							melds[i].cards = sort_run(melds[i].cards)
						success = true
					break
			if success: break
			
	if success and extracted_joker != null:
		if must_play_card_id == replacement_card_id:
			must_play_card_id = null

		var new_hand = []
		for c in cp.hand:
			if c.id != replacement_card_id: new_hand.append(c)
		new_hand.append(extracted_joker)
		cp.hand = sort_hand(new_hand)
		last_draw_snapshot = {}
		message = "Вы успешно выкупили Джокера! Он возвращен в вашу руку."
		state_changed.emit()
		return true
		
	message = "Ошибка: Карта не совпадает с Джокером."
	state_changed.emit()
	return false

func end_round():
	phase = "ROUND_OVER"
	last_draw_snapshot = {}
	for p in players:
		var hand_score = 0
		for c in p.hand: hand_score += get_card_value(c, true)
		
		var table_score = 0
		for m in melds:
			for c in m.cards:
				if c.get("ownerId", -1) == p.id:
					table_score += get_card_value(c, false)
					
		p.globalScore += (table_score - hand_score)
		
	var winner = null
	for p in players:
		if p.globalScore >= target_score:
			winner = p
			break
			
	if winner != null:
		phase = "GAME_OVER"
		message = "Игра окончена! Победитель: %s с %d очками!" % [winner.name, winner.globalScore]
	else:
		round_number += 1
		message = "Раунд завершен! Нажмите 'Следующий раунд'."
	state_changed.emit()

func get_card_value(card: Dictionary, _in_hand: bool) -> int:
	if card.isJoker: return 15
	if card.rank in ["В", "Д", "К"]: return 10
	if card.rank == "Т": return 15
	return 5  # cards 2-9

func can_undo_draw() -> bool:
	return phase == "ACTION" and not last_draw_snapshot.is_empty()

func undo_last_draw() -> bool:
	if not can_undo_draw(): return false
	if last_draw_snapshot.get("player_index", -1) != current_player_index: return false
	players = last_draw_snapshot["players"].duplicate(true)
	current_player_index = last_draw_snapshot["current_player_index"]
	deck = last_draw_snapshot["deck"].duplicate(true)
	discard_pile = last_draw_snapshot["discard_pile"].duplicate(true)
	melds = last_draw_snapshot["melds"].duplicate(true)
	phase = "DRAW"
	must_play_card_id = last_draw_snapshot["must_play_card_id"]
	message = "Взятие отменено. Выберите действие заново."
	last_draw_snapshot = {}
	state_changed.emit()
	return true

func _capture_draw_snapshot():
	last_draw_snapshot = {
		"players": players.duplicate(true),
		"current_player_index": current_player_index,
		"deck": deck.duplicate(true),
		"discard_pile": discard_pile.duplicate(true),
		"melds": melds.duplicate(true),
		"must_play_card_id": must_play_card_id,
		"player_index": current_player_index
	}

func _has_potential_meld_with_target(cards: Array, target_id: String) -> bool:
	var target = null
	for c in cards:
		if c.id == target_id:
			target = c
			break
	if target == null: return false
	var others = []
	for c in cards:
		if c.id != target_id:
			others.append(c)
	if others.size() < 2: return false
	for i in range(others.size() - 1):
		for j in range(i + 1, others.size()):
			var attempt = [target, others[i], others[j]]
			if _is_potential_group(attempt) or _is_potential_run(attempt):
				return true
	return false

func _is_potential_group(cards: Array) -> bool:
	var regular = []
	for c in cards:
		if not c.isJoker:
			regular.append(c)
	if regular.is_empty(): return true
	var r = regular[0].get("rank", null)
	if r == null: return false
	for c in regular:
		if c.get("rank", null) != r:
			return false
	var suit_set = {}
	for c in regular:
		var s = c.get("suit", null)
		if s == null: return false
		if suit_set.has(s): return false
		suit_set[s] = true
	return true

func _is_potential_run(cards: Array) -> bool:
	var regular = []
	for c in cards:
		if not c.isJoker:
			regular.append(c)
	if regular.is_empty(): return true
	var suit = regular[0].get("suit", null)
	if suit == null: return false
	for c in regular:
		if c.get("suit", null) != suit:
			return false
	var idx = []
	for c in regular:
		var rank = c.get("rank", null)
		if rank == null: return false
		var v = ranks.find(rank)
		if v == -1: return false
		if v in idx: return false
		idx.append(v)
	var run_len = cards.size()
	for start in range(ranks.size()):
		var win = []
		for off in range(run_len):
			win.append((start + off) % ranks.size())
		var ok = true
		for v in idx:
			if not v in win:
				ok = false
				break
		if ok: return true
	return false

func get_valid_joker_assignments(test_cards: Array, meld_id: String = "") -> Array:
	var valid = []
	var j_index = -1
	
	var full_test = test_cards.duplicate(true)
	if meld_id != "":
		for m in melds:
			if m.id == meld_id:
				var m_cards = m.cards.duplicate(true)
				m_cards.append_array(full_test)
				full_test = m_cards
				break
				
	for i in range(full_test.size()):
		var c = full_test[i]
		if c.isJoker and not c.has("jokerAssumedRank"):
			j_index = i
			break
			
	if j_index == -1: return []
	
	var j = full_test[j_index]
	
	for s in suits:
		for r in ranks:
			j["jokerAssumedSuit"] = s
			j["jokerAssumedRank"] = r
			if is_valid_group(full_test) or is_valid_run(full_test):
				valid.append({"suit": s, "rank": r})
					
	j.erase("jokerAssumedSuit")
	j.erase("jokerAssumedRank")
	return valid

func _ready():
	if _is_server():
		state_changed.connect(_broadcast_state)
