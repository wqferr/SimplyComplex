BASE_PATH_THICKNESS = 5
MAX_PATH_THICKNESS = 40

INPUT_MIN = {-2, -2}
INPUT_MAX = {3, 3}
OUTPUT_MIN = INPUT_MIN
OUTPUT_MAX = INPUT_MAX

INPUT_AREA = (INPUT_MAX[1] - INPUT_MIN[1]) * (INPUT_MAX[2] - INPUT_MIN[2])
OUTPUT_AREA = (OUTPUT_MAX[1] - OUTPUT_MIN[1]) * (OUTPUT_MAX[2] - OUTPUT_MIN[2])
STROKE_WIDTH_SCALING_FACTOR = math.sqrt(OUTPUT_AREA / INPUT_AREA)

MAX_PIXEL_DISTANCE_BEFORE_INTERP = 20
INTERP_STEPS = 5
MAX_INTERP_TRIES = 3
MIN_PIXEL_DIST_FOR_NEW_POINT = 5
CLOSE_PATH_DIST = 20

OUTPUT_HOVER_POINT_CROSS_SIZE = 7

DEFAULT_FUNC = "z^2"
