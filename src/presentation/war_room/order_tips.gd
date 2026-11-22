class_name OrderTips
extends RefCounted
## Hover tooltips for every battle order (sw-ll4.27.5): what the order does,
## how the squad's weapons behave under it, its costs and its key as GUIDE
## reports it. Rules text from GDD 02 §2.6. Every string goes through a
## translation key ("order.<id>.name|effect|weapons|cost"), with the English
## below as the fallback until translation tables exist. Presentation only.

## Orders in display order. `action` is the PlanningInput action that sets it
## (&"" = pointer-only).
const ORDERS: Array = [
	{"id": "move", "action": &""},
	{"id": "attack_move", "action": &"attack_move"},
	{"id": "attack", "action": &""},
	{"id": "hold", "action": &"hold"},
	{"id": "fall_back", "action": &"fall_back"},
	{"id": "withdraw", "action": &"withdraw"},
	{"id": "run", "action": &"run"},
	{"id": "abilities", "action": &"abilities"},
]

## Reaction names to the order they queue.
const REACTION_ORDER: Dictionary = {"halt": "hold", "fall_back": "fall_back", "retarget": "attack"}

const EN: Dictionary = {
	"order.move.name": "Move",
	"order.move.effect": "Walks the squad to the point you right click.",
	"order.move.weapons": "Weapons that can fire on the move do so; mortars and other static weapons cannot fire while moving.",
	"order.move.cost": "Firing on the move sinks Instinct.",
	"order.attack_move.name": "Attack-move",
	"order.attack_move.effect": "Advances to the point, stopping to engage any enemy seen on the way.",
	"order.attack_move.weapons": "Stands and fires while its weapons reload, then moves on; mortars cannot fire while moving.",
	"order.attack_move.cost": "Firing on the move sinks Instinct.",
	"order.attack.name": "Attack",
	"order.attack.effect": "Right click an enemy: closes in until it has a shot at it.",
	"order.attack.weapons": "Stands while its weapons reload, firing as soon as the target is in range and in sight; mortars cannot fire while moving.",
	"order.attack.cost": "Firing on the move sinks Instinct.",
	"order.hold.name": "Hold",
	"order.hold.effect": "Stays put and shoots anything that comes into reach.",
	"order.hold.weapons": "All weapons fire freely.",
	"order.hold.cost": "None.",
	"order.fall_back.name": "Fall back",
	"order.fall_back.effect": "Retreats from the enemy toward your side of the map.",
	"order.fall_back.weapons": "Holds fire while falling back.",
	"order.fall_back.cost": "The squad gives up its ground and stops fighting while it moves.",
	"order.withdraw.name": "Withdraw",
	"order.withdraw.effect": "Leaves the battle for good; the squad is out once it reaches the edge.",
	"order.withdraw.weapons": "Holds fire while withdrawing.",
	"order.withdraw.cost": "The squad cannot return to this battle.",
	"order.run.name": "Run",
	"order.run.effect": "Moves at a sprint on its current order.",
	"order.run.weapons": "Weapons fire at worse accuracy, or not at all, while running.",
	"order.run.cost": "Sinks Stamina.",
	"order.abilities.name": "Abilities",
	"order.abilities.effect": "Opens the menu of abilities the selected squads can use now.",
	"order.abilities.weapons": "Each ability says what it does; toggled ones stay on until switched off.",
	"order.abilities.cost": "Each ability pays its own costs, often Instinct.",
	"order.tip.key": "Key: {key}",
	"order.tip.unbound": "Key: none",
	"order.tip.weapons": "Weapons: {text}",
	"order.tip.cost": "Cost: {text}",
}


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for o: Dictionary in ORDERS:
		out.append(o["id"])
	return out


## The translation keys an order's tooltip is made of.
static func keys_of(id: String) -> PackedStringArray:
	return PackedStringArray(["order.%s.name" % id, "order.%s.effect" % id, "order.%s.weapons" % id, "order.%s.cost" % id])


static func name_of(id: String) -> String:
	return _t("order.%s.name" % id)


## The action an order is bound to, &"" for pointer-only orders.
static func action_of(id: String) -> StringName:
	for o: Dictionary in ORDERS:
		if o["id"] == id:
			return o["action"]
	return &""


## The key text of an order's action from the planning context ("H", "Shift+W"),
## "" if the order has no key (pointer-only) or the key is unbound.
static func key_of(id: String, p: PlanningInput = null) -> String:
	var action := action_of(id)
	if action == &"":
		return ""
	var own := p == null
	if own:
		p = PlanningInput.new()
	var ims: Array = []
	for m: GUIDEActionMapping in p.context.mappings:
		if m.action.name == action:
			for im: GUIDEInputMapping in m.input_mappings:
				ims.append(GuideKeys.key_text(im.input))
	if own:
		p.free()
	return " / ".join(ims)


## The tooltip text of an order: name, effect, weapon behaviour, costs, key.
static func tip(id: String, p: PlanningInput = null) -> String:
	if not ids().has(id):
		return ""
	var lines := PackedStringArray([
		_t("order.%s.name" % id), _t("order.%s.effect" % id),
		_t("order.tip.weapons").format({"text": _t("order.%s.weapons" % id)}),
		_t("order.tip.cost").format({"text": _t("order.%s.cost" % id)})])
	if action_of(id) != &"":
		var key := key_of(id, p)
		lines.append(_t("order.tip.key").format({"key": key}) if key != "" else _t("order.tip.unbound"))
	return "\n".join(lines)


## The tooltip of a reaction (halt, fall_back, retarget), from its order.
static func reaction_tip(reaction: String) -> String:
	var id: String = REACTION_ORDER.get(reaction, "")
	return tip(id) if id != "" else reaction.capitalize()


static func _t(key: String) -> String:
	var s := String(TranslationServer.translate(key))
	return EN.get(key, key) if s == key else s
