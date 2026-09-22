class_name RouteGraphData
# Static graph matching v4 SVG mockup - only routing + multiple starts/ends, no 1-in/1-out filler
# Conditions live on ports, not separate nodes

static func get_nodes() -> Array[Dictionary]:
	var nodes: Array[Dictionary] = [
		{
			"id": "start_forest",
			"type": "START",
			"color": Color("#16A34A"),
			"title": "Forest Edge",
			"full": "Forest Edge Dawn",
			"x": 30, "y": 80, "w": 230, "h": 135,
			"inputs": [],
			"outputs": [
				{"type": "FLOW", "tag": "OUT", "label": "crossroads", "target": "crossroads", "full_dest": "Ancient Crossroads of Whispering Winds", "cond": ""},
			],
			"subtitle": "entry • 0 in / 1 out",
			"has_conds": false
		},
		{
			"id": "start_cave",
			"type": "START",
			"color": Color("#16A34A"),
			"title": "Cave Mouth",
			"full": "Cave Mouth Entrance of Echoes",
			"x": 30, "y": 260, "w": 230, "h": 135,
			"inputs": [],
			"outputs": [
				{"type": "FLOW", "tag": "OUT", "label": "Cave Path", "target": "cave_path", "full_dest": "Cave Path", "cond": ""},
			],
			"subtitle": "entry • direct",
			"has_conds": false
		},
		{
			"id": "start_village",
			"type": "START",
			"color": Color("#16A34A"),
			"title": "Village Outskirts",
			"full": "Village Outskirts at Night With Wolves Howling Far Away",
			"x": 30, "y": 440, "w": 230, "h": 145,
			"inputs": [],
			"outputs": [
				{"type": "FLOW", "tag": "OUT", "label": "crossroads", "target": "crossroads", "full_dest": "Ancient Crossroads of Whispering Winds", "cond": "night == true"},
			],
			"subtitle": "entry • alt",
			"has_conds": true
		},
		{
			"id": "crossroads",
			"type": "ROUTE",
			"color": Color("#0F766E"),
			"title": "Crossroads",
			"full": "Ancient Crossroads of Whispering Winds",
			"x": 320, "y": 150, "w": 300, "h": 250,
			"inputs": [
				{"type": "FLOW", "tag": "FROM", "label": "Forest Edge", "source": "start_forest", "full_src": "Forest Edge Dawn", "cond": ""},
				{"type": "FLOW", "tag": "FROM", "label": "start_village", "source": "start_village", "full_src": "Village Outskirts at Night With Wolves Howling Far Away", "cond": ""},
			],
			"outputs": [
				{"type": "STORY", "tag": "PATH_A", "label": "Help Stranger?", "target": "help_stranger", "full_dest": "Help Stranger?", "cond": ""},
				{"type": "CHOICE", "tag": "PATH_B", "label": "Cave Path", "target": "cave_path", "full_dest": "Cave Path", "cond": "has_torch == false"},
			],
			"subtitle": "2 in / 2 out • routing",
			"has_conds": true
		},
		{
			"id": "help_stranger",
			"type": "CHOICE",
			"color": Color("#D97706"),
			"title": "Help Stranger?",
			"full": "Help Stranger?",
			"x": 680, "y": 100, "w": 320, "h": 310,
			"inputs": [
				{"type": "STORY", "tag": "IN", "label": "crossroads", "source": "crossroads", "full_src": "Ancient Crossroads of Whispering Winds", "cond": ""},
			],
			"outputs": [
				{"type": "CHOICE", "tag": "YES", "label": "rt_forest", "target": "whisper_forest", "full_dest": "The Whispering Forest Path of Forgotten Ancient Lights", "cond": "has_lantern == true"},
				{"type": "CHOICE", "tag": "YES", "label": "Cave Path", "target": "cave_path", "full_dest": "Cave Path", "cond": "has_lantern == false"},
				{"type": "CHOICE", "tag": "NO", "label": "end_death", "target": "end_death", "full_dest": "Betrayed and Left to Die Alone in Cold", "cond": ""},
			],
			"subtitle": "1 in / 3 out • cond on ports",
			"has_conds": true
		},
		{
			"id": "whisper_forest",
			"type": "ROUTE",
			"color": Color("#0D9488"),
			"title": "Whispering Forest",
			"full": "The Whispering Forest Path of Forgotten Ancient Lights",
			"x": 1060, "y": 50, "w": 310, "h": 250,
			"inputs": [
				{"type": "CHOICE", "tag": "YES", "label": "Help Stranger?", "source": "help_stranger", "full_src": "Help Stranger?", "cond": "has_lantern"},
			],
			"outputs": [
				{"type": "FLOW", "tag": "LIGHT", "label": "end_true", "target": "end_true", "full_dest": "True Dawn Ending of Light and Shadow Reunited Together Forever", "cond": "has_amulet == true"},
				{"type": "FLOW", "tag": "SECRET", "label": "Secret Grove", "target": "end_secret", "full_dest": "Secret Grove", "cond": "has_amulet == false"},
			],
			"subtitle": "1 in / 2 out • amulet",
			"has_conds": true,
			"truncated": true
		},
		{
			"id": "cave_path",
			"type": "ROUTE",
			"color": Color("#EA580C"),
			"title": "Cave Path",
			"full": "Cave Path",
			"x": 1060, "y": 350, "w": 310, "h": 300,
			"inputs": [
				{"type": "FLOW", "tag": "DIRECT", "label": "start_cave", "source": "start_cave", "full_src": "Cave Mouth Entrance of Echoes", "cond": ""},
				{"type": "CHOICE", "tag": "PATH_B", "label": "crossroads", "source": "crossroads", "full_src": "Ancient Crossroads of Whispering Winds", "cond": "has_torch == false"},
				{"type": "CHOICE", "tag": "YES", "label": "Help Stranger?", "source": "help_stranger", "full_src": "Help Stranger?", "cond": "!has_lantern"},
			],
			"outputs": [
				{"type": "FLOW", "tag": "DEEP", "label": "Lost in Dark", "target": "end_dark", "full_dest": "Lost in Dark", "cond": ""},
				{"type": "FLOW", "tag": "HIDDEN", "label": "Secret Grove", "target": "end_secret", "full_dest": "Secret Grove", "cond": "has_lantern"},
			],
			"subtitle": "3 in / 2 out • converge",
			"has_conds": true
		},
		{
			"id": "end_true",
			"type": "ENDING",
			"color": Color("#DB2777"),
			"title": "True Dawn",
			"full": "True Dawn Ending of Light and Shadow Reunited Together Forever",
			"x": 1430, "y": 50, "w": 220, "h": 140,
			"inputs": [
				{"type": "FLOW", "tag": "LIGHT", "label": "rt_forest", "source": "whisper_forest", "full_src": "The Whispering Forest Path of Forgotten Ancient Lights", "cond": ""},
			],
			"outputs": [],
			"subtitle": "TRUE END",
			"truncated": true
		},
		{
			"id": "end_secret",
			"type": "ENDING",
			"color": Color("#8B5CF6"),
			"title": "Secret Grove",
			"full": "Secret Grove",
			"x": 1430, "y": 230, "w": 220, "h": 170,
			"inputs": [
				{"type": "FLOW", "tag": "SECRET", "label": "rt_forest", "source": "whisper_forest", "full_src": "The Whispering Forest Path of Forgotten Ancient Lights", "cond": ""},
				{"type": "FLOW", "tag": "HIDDEN", "label": "Cave Path", "source": "cave_path", "full_src": "Cave Path", "cond": "has_lantern"},
			],
			"outputs": [],
			"subtitle": "2 in • secret",
			"has_conds": true
		},
		{
			"id": "end_dark",
			"type": "ENDING",
			"color": Color("#475569"),
			"title": "Lost in Dark",
			"full": "Lost in Dark",
			"x": 1430, "y": 440, "w": 220, "h": 135,
			"inputs": [
				{"type": "FLOW", "tag": "DEEP", "label": "Cave Path", "source": "cave_path", "full_src": "Cave Path", "cond": ""},
			],
			"outputs": [],
			"subtitle": "BAD END"
		},
		{
			"id": "end_death",
			"type": "ENDING",
			"color": Color("#991B1B"),
			"title": "Betrayed",
			"full": "Betrayed and Left to Die Alone in Cold",
			"x": 1060, "y": 690, "w": 310, "h": 135,
			"inputs": [
				{"type": "CHOICE", "tag": "NO", "label": "Help Stranger?", "source": "help_stranger", "full_src": "Help Stranger?", "cond": ""},
			],
			"outputs": [],
			"subtitle": "1 in • death",
			"truncated": true
		},
	]
	return nodes

static func display_label(full_text: String, fallback_id: String, short_label: String) -> String:
	if full_text.length() > 16:
		return fallback_id
	return short_label
