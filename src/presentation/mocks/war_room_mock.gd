extends RefCounted
## Mock (sw-ip8.2, sw-ip8.3, sw-ll4.19): the war room in four states on one sheet, fed by
## the demo OverworldSession: the overworld with a commander selected (its
## reach lit) and the battles menu, a
## focused battle with a second battle in a picture-in-picture view, and
## planning (sw-ip8.3): a selection with a drafted move into a new line,
## its intent ghosts and the order and ability panel; and a battle turn
## halfway through its playback. Render
## with `hx godot mock res://src/presentation/mocks/war_room_mock.gd`.
## The overworld (sw-63wt.5) is the hex view at zoom 1: the village on the
## road at the left stands off it, and the hex north-west of the camera's
## commander holds three sites (a depot and a mine of player 1's, a shrine).

const FRAME := Vector2(1230, 680)
const GAP := 16.0


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(FRAME.x * 2 + GAP * 3, FRAME.y * 2 + GAP * 3)
	var bg := ColorRect.new()
	bg.color = Color("0b0d10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	for i in 4:
		var holder := Control.new()
		holder.position = Vector2(GAP + (i % 2) * (FRAME.x + GAP), GAP + (i / 2) * (FRAME.y + GAP))
		holder.size = FRAME
		root.add_child(holder)
		var w: WarRoom = load("res://src/presentation/war_room/war_room.tscn").instantiate()
		w.demo_view = ["move", "pip", "plan", "play"][i]
		if i == 0:
			w.session = _three_sites()
		holder.add_child(w)
	return root


## The demo session with three sites on the hex north-west of player 1's
## first commander (the camera's), seen by player 1.
static func _three_sites() -> OverworldSession:
	var s := WarRoom.demo_session()
	var st := s.state
	var w := s.rules.width
	var first := -1
	for row in st.commanders.count():
		if st.commanders.player[row] == 1 and (first < 0 or st.commanders.id_at(row) < st.commanders.id_at(first)):
			first = row
	var at := Hex.plot_of(Hex.axial_of(st.commanders.plot[first], w) + Hex.DIRS[2], w, s.rules.height)
	st.add_feature(at, s.rules.feature_index("hex_depot"), 1)
	st.add_feature(at, s.rules.feature_index("hex_mine"), 1)
	st.add_feature(at, s.rules.feature_index("hex_shrine"), 0)
	OverworldVision.update(st)
	return s
