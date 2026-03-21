extends RefCounted
class_name BattlefieldLayout
## Shared dimensions for battlefield view and simulation (world vs screen mapping).

const BATTLEFIELD_WIDTH: float = 200.0
const BATTLEFIELD_HEIGHT: float = 100.0
const WORLD_SCALE: float = 5.0
const BOARD_ORIGIN: Vector2 = Vector2(100, 80)

const RESERVE_PANEL_X_OFFSET: float = 60.0
const RESERVE_PANEL_Y_OFFSET: float = 120.0
const RESERVE_UNIT_SPACING_Y: float = 26.0
const RESERVE_SLOT_SIZE := Vector2(28, 16)

const MODEL_DIAMETER_WORLD: float = 1.0
const FORMATION_FILES: int = 5
const FORMATION_RANKS: int = 2

const BATCH_DEPLOY_SPACING_X: float = 4.0

static func board_rect() -> Rect2:
	return Rect2(BOARD_ORIGIN, Vector2(BATTLEFIELD_WIDTH * WORLD_SCALE, BATTLEFIELD_HEIGHT * WORLD_SCALE))
