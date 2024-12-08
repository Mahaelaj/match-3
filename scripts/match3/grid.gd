extends Node2D

@onready var pieces_container = $PiecesContainer

var blue_match_piece = preload("res://scenes/match3/piece_blue.tscn")
var beige_match_piece = preload("res://scenes/match3/piece_beige.tscn")
var green_match_piece = preload("res://scenes/match3/piece_green.tscn")
var yellow_match_piece = preload("res://scenes/match3/piece_yellow.tscn")
var pink_match_piece = preload("res://scenes/match3/piece_pink.tscn")
var pieces_scn = [
	blue_match_piece,
	beige_match_piece,
	green_match_piece,
	yellow_match_piece,
	pink_match_piece,
]

const all_color_special_piece = preload("res://scenes/match3/all_color_piece.tscn")
const line_horizontal_piece = preload("res://scenes/match3/line_horizontal_piece.tscn")
const line_verticle_piece = preload("res://scenes/match3/line_verticle_piece.tscn")
const bomb_piece = preload("res://scenes/match3/bomb_piece.tscn")

# Grid start position (pixels) in x-axis direction
var x_start: = 70
# Grid start position (pixels) in y-axis direction
var y_start: = 910
# Size of one grid (should be the same as Texture of Sprite in Piece)
var grid_size: = 70

# A two-dimensional array (initially empty) that manages all the pieces of the board as elements and their grid coordinates
var all_pieces = []

# Position where finger touches the screen
var touched_pos = Vector2()
# The position where the finger leaves the screen
var released_pos = Vector2()

# State where finger is touching the screen, touched: true / away: false
var is_touching = false
# State of automatic processing of matching, processing: true / stopped: false
var is_waiting = false

var pieceMovementSpeed = 250
var userSelectedPiece = null
var userTargetedPiece = null

var movingPieces = []

var curMovementRound = 0

enum Stage {WAITING_FOR_USER_INPUT, USER_SELECTED_FIRST_PIECE, SWAPPING_USER_PIECES, REVERSING_USER_SWAP, COLLAPSING}
var curStage = Stage.WAITING_FOR_USER_INPUT


var gridConfig = GridConfig.LEVEL_1
# Number of grids in x-axis direction
var width = gridConfig.front().size()
# Number of grids in y-axis direction
var height = gridConfig.size()

# Called when the node enters the scene tree for the first time.
func _ready():
	# Method to randomize the output result of a function that generates a random number each time
	randomize()
	
	all_pieces = make_2d_array() 
	spawn_match_pieces()


func _process(_delta):
	if (movingPieces.is_empty()):
		return
		
	var isFinishedMovingList = movingPieces.map(func(movingPiece): return movingPiece.move(pieceMovementSpeed, _delta))
	var isAllFinishedMoving = isFinishedMovingList.all(func(isFinished): return isFinished)
	if (!isAllFinishedMoving):
		return
	movingPieces = []
	
	if (curStage == Stage.SWAPPING_USER_PIECES):
		update_piece_movement_round([userSelectedPiece, userTargetedPiece], true)
		var didRemoveMatches = await remove_matches()
		if(didRemoveMatches):
			curStage = Stage.COLLAPSING
		else:
			update_piece_movement_round([userSelectedPiece, userTargetedPiece], false)
			swap_pieces(userSelectedPiece, userTargetedPiece)
			curStage = Stage.REVERSING_USER_SWAP
	if (curStage == Stage.REVERSING_USER_SWAP):
		set_waiting_for_user_input()
	if (curStage == Stage.COLLAPSING):
		var didCollapseColumn = collapse_columns()
		if (didCollapseColumn):
			return 
		var didRemoveMatches = await remove_matches()
		if(didRemoveMatches):
			collapse_columns()
		else:
			set_waiting_for_user_input()
				
func update_piece_movement_round(pieces, increment):
	if increment: 
		curMovementRound += 1
	else: 
		curMovementRound -= 1
	for piece in pieces:
		piece.lastRoundMoved = curMovementRound

func set_waiting_for_user_input():
	curStage = Stage.WAITING_FOR_USER_INPUT
	userSelectedPiece = null
	userTargetedPiece = null
	
func make_2d_array():
	# Prepare an array named array for output
	var array = []
	# Fill the prepared array with the number of empty arrays for the number of grids along the x-axis
	for h in height + 1:
		array.append([])
		# Add a value of null for the number of grids in the y-axis to each array
		for w in width:
			array[h].append(null)
	# return the two-dimensional array
	return array

# Method to spawn pieces and place them on each grid
func spawn_match_pieces():
	for h in height:
		for w in width:
			# If no piece exists in the corresponding grid on the 2D array of all pieces
			# (All null at the start of the game)
			if all_pieces[h][w] == null:
				if (gridConfig[height - 1 - h][w] == "bl"):
					var piece = blue_match_piece.instantiate()
					add_piece_to_grid(h, w, piece)
				elif (gridConfig[height - 1 - h][w] == "ye"):
					var piece = yellow_match_piece.instantiate()
					add_piece_to_grid(h, w, piece)
				else:
					spawn_random_match_piece(h, w, true)
				# Randomly select one from the scenes of each color and instantiate it
	for w in width:
		spawn_random_match_piece(height, w, true)
				
func spawn_random_match_piece(h, w, preventMatch):
	var index = floor(randf_range(0, pieces_scn.size()))
	var piece = pieces_scn[index].instantiate()
	# If it matches, delete the piece instance and start over
	if (preventMatch):
		while match_at(h, w, piece.color): # define after this
			piece.queue_free()
			index = floor(randf_range(0, pieces_scn.size()))
			piece = pieces_scn[index].instantiate()

	add_piece_to_grid(h, w, piece)
		
func add_piece_to_grid(h, w, piece):
		# Make a piece instance a child of a PiecesContainer node
	pieces_container.add_child(piece)
	# Place the piece instance at the position converted from grid to pixels
	piece.position = grid_to_pixel(h, w) # define after this
	# Update the 2D array of all pieces
	all_pieces[h][w] = piece
	piece.pressed.connect(_piece_selected.bind(piece))
	piece.mouseEntered.connect(_piece_mouse_entered.bind(piece))
	piece.released.connect(_piece_released.bind(piece))
	if (h == height):
		piece.isInReserve = true
	
func match_at(row, column, color):
	# If the x-axis value of the specified grid coordinate is 3 or greater
	if row >= 2:
		# If there is a piece to the left of the specified grid coordinate and one more to the left
		if all_pieces[row-1][column] != null \
		and  all_pieces[row-2][column] != null:
			# If the color of those pieces is the same as the color of the given piece
				if all_pieces[row-1][column].color == color \
				and all_pieces[row-2][column].color == color:
					# Return true
					return true
	## If the y-axis value of the specified grid coordinate is 3 or greater
	if column >= 2:
		# If there are pieces below the specified grid coordinates and one more below
		if all_pieces[row][column-1] != null \
		and all_pieces[row][column-2] != null:
			# If the color of those pieces is the same as the color of the given piece
			if all_pieces[row][column-1].color == color \
			and all_pieces[row][column-2].color == color:
				# return true
				return true
	
	if (row > 0 && column > 0 \
	and all_pieces[row][column-1] != null \
	and all_pieces[row - 1][column] != null \
	and all_pieces[row - 1][column - 1] != null \
	and all_pieces[row][column-1].color == color \
	and all_pieces[row - 1][column].color == color \
	and all_pieces[row - 1][column - 1].color == color):
		return true
	
	if (row < height - 1 && column > 0 \
	and all_pieces[row][column-1] != null \
	and all_pieces[row + 1][column] != null \
	and all_pieces[row + 1][column - 1] != null \
	and all_pieces[row][column-1].color == color \
	and all_pieces[row + 1][column].color == color \
	and all_pieces[row + 1][column - 1].color == color):
		return true
	
	if (row < height - 1 and column < width - 1 \
	and all_pieces[row][column+1] != null \
	and all_pieces[row + 1][column] != null \
	and all_pieces[row + 1][column + 1] != null \
	and all_pieces[row][column + 1].color == color \
	and all_pieces[row + 1][column].color == color \
	and all_pieces[row + 1][column + 1].color == color):
		return true
		
	if (row > 0 && column < width - 1 
	and all_pieces[row][column+1] != null \
	and all_pieces[row - 1][column] != null \
	and all_pieces[row - 1][column + 1] != null \
	and all_pieces[row][column + 1].color == color \
	and all_pieces[row - 1][column].color == color \
	and all_pieces[row - 1][column + 1].color == color):
		return true

# Method to convert grid position to pixel position
func grid_to_pixel(row, column):
	# Define a Vector2 variable pixel_pos for pixel position output
	var pixel_pos = Vector2()
	# Pixel x-coordinate = grid start position along x-axis + grid size * grid x-coordinate
	pixel_pos.x = x_start + grid_size * column
	# Pixel y-coordinate = grid start position along y-axis - grid size * grid y-coordinate
	pixel_pos.y = y_start - grid_size * row
	# Return pixel position
	return pixel_pos

# Method to convert pixel position to grid position
func pixel_to_grid(pixel_x, pixel_y) -> Vector2:
	var grid_pos = Vector2()
	grid_pos.x = floor((pixel_x - x_start) / grid_size)
	grid_pos.y = floor((pixel_y - y_start) / -grid_size)
	return grid_pos
	
# Method to check if there is at least one matched piece and return the result
func check_matches() -> bool:
	# Loop over the x-axis grid of the board
	for h in height:
		# Loop over the y-axis grid of the board
		for w in width:
			# if piece exists at that grid coordinate
			if all_pieces[h][w] != null:
				# return true if the piece matches at that grid coordinate, and method also terminates
				if match_at(h, w, all_pieces[h][w].color):
					return true
	# Check all pieces and return false if none of them match
	return false
	
# Find matching pieces and flag method
func find_matches() -> bool:
	var foundMatch = false
	# Loop over the number of x-axis grids on the board
	for h in height:
		# Loop over the number of y-axis grids on the board
		for w in width:
			# If a piece exists at the coordinates of that grid
			if all_pieces[h][w] != null and all_pieces[h][w] is MatchPiece:
				# Define the current color as the color of that piece
				var current_color = all_pieces[h][w].color
				# If its x-axis coordinates are less than the number of x-axis grids - 2
				if h < height - 2:
					# If there are pieces to the right of that piece and further to its right
					if all_pieces[h + 1][w] != null \
					and all_pieces[h + 2][w] != null \
					and all_pieces[h + 1][w] is MatchPiece \
					and all_pieces[h + 2][w] is MatchPiece \
					and all_pieces[h + 1][w].color == current_color \
					and all_pieces[h + 2][w].color == current_color:
						foundMatch = true
						all_pieces[h][w].make_matched()
						all_pieces[h + 1][w].make_matched()
						all_pieces[h + 2][w].make_matched()
				# If the piece's y-coordinate is less than the number of grids along the y-axis - 2
				if w < width - 2:
					# If there are pieces above and further to its above that piece
					if all_pieces[h][w + 1] != null \
					and all_pieces[h][w + 2] != null \
					and all_pieces[h][w + 1] is MatchPiece \
					and all_pieces[h][w + 2] is MatchPiece \
					and all_pieces[h][w + 1].color == current_color \
					and all_pieces[h][w + 2].color == current_color:
						foundMatch = true
						all_pieces[h][w].make_matched()
						all_pieces[h][w + 1].make_matched()
						all_pieces[h][w + 2].make_matched()
						
				if (h < height - 1 && w < width - 1):
					if all_pieces[h + 1][w] != null \
					and all_pieces[h][w + 1] != null \
					and all_pieces[h + 1][w + 1] != null \
					and all_pieces[h + 1][w] is MatchPiece \
					and all_pieces[h][w + 1] is MatchPiece \
					and all_pieces[h + 1][w + 1] is MatchPiece \
					and all_pieces[h + 1][w].color == current_color \
					and all_pieces[h][w + 1].color == current_color \
					and all_pieces[h + 1][w + 1].color == current_color:
						foundMatch = true
						all_pieces[h][w].make_matched()
						all_pieces[h + 1][w].make_matched()
						all_pieces[h][w + 1].make_matched()
						all_pieces[h + 1][w + 1].make_matched()
					
	return foundMatch

# Method to delete matched pieces
func delete_matches():
	# Loop over the number of x-axis grids on the board
	for h in height:
		# Loop over the number of y-axis grids of the board
		for w in width:
			# If a piece exists at that grid coordinate
			if all_pieces[h][w] != null:
				 # If a piece at that grid coordinate is flagged
				if all_pieces[h][w].isMatched:
					delete_piece(h,w)
					
					
func delete_piece(h, w):
	all_pieces[h][w].queue_free()
	# Empty the element with that grid coordinate from the 2D array of all_pieces[i][j].queue_free()
	all_pieces[h][w] = null
	
					
# Method to collapse a column by moving the piece above it in a space where no piece exists
func collapse_columns():
	var collapsedColumns = []
			
	# Loop over the number of x-axis grids in the board
	for h in height:
		# Loop over the number of y-axis grids in the board
		for w in width:
			# If no piece exists at that grid coordinate (null)
			if all_pieces[h][w] == null:
				# Loop from one row above the y-coordinate of that grid to the top row
					# If a piece exists on the grid one above
				if all_pieces[h + 1][w] != null:
					## Move the piece on the grid above to an empty grid below
					movingPieces.append(MovingPiece.new(all_pieces[h + 1][w], grid_to_pixel(h, w)))
					## Put one piece above into the current grid coordinates of the 2D array of all_pieces
					all_pieces[h][w] = all_pieces[h + 1][w]
					## Empty the grid coordinate one above in the 2D array of all_pieces
					all_pieces[h + 1][w] = null
					all_pieces[h][w].isInReserve = false
					collapsedColumns.append(all_pieces[h][w])
					
	for w in width:
		if (all_pieces[height][w] == null):
			spawn_random_match_piece(height, w, false)
					
	update_piece_movement_round(collapsedColumns, true)
	return !collapsedColumns.is_empty()
						
func _piece_selected(piece):
	if (curStage == Stage.WAITING_FOR_USER_INPUT && movingPieces.is_empty()):
		userSelectedPiece = piece
		curStage = Stage.USER_SELECTED_FIRST_PIECE
		
func _piece_released(piece):
	if (curStage == Stage.USER_SELECTED_FIRST_PIECE):
		if (piece is MatchPiece):
			userSelectedPiece = null
			curStage = Stage.WAITING_FOR_USER_INPUT
		elif (piece is SpecialPiece):
			match(piece.type):
				SpecialPiece.Type.ALL_COLOR:
					var color = find_most_prominent_color()
					trigger_all_color_special(piece, color)
			collapse_columns()
			curStage = Stage.COLLAPSING
	
func _piece_mouse_entered(targetPiece):
	if (curStage != Stage.USER_SELECTED_FIRST_PIECE || \
	userSelectedPiece == null || \
	userSelectedPiece == targetPiece):
		return
	userTargetedPiece = targetPiece
	swap_pieces(userSelectedPiece, targetPiece)
	curStage = Stage.SWAPPING_USER_PIECES
		
func swap_pieces(piece1, piece2):
	var piece1X
	var piece1Y
	var piece2X
	var piece2Y
	for h in height:
		for w in width:
			if (all_pieces[h][w] == piece1):
				piece1X = h
				piece1Y = w
			if (all_pieces[h][w] == piece2): 
				piece2X = h
				piece2Y = w
	if ((abs(piece1X - piece2X) == 1 && piece1Y == piece2Y) \
	or (abs(piece1Y - piece2Y) == 1 && piece1X == piece2X)):
		all_pieces[piece1X][piece1Y] = piece2
		all_pieces[piece2X][piece2Y] = piece1
	movingPieces.push_back(MovingPiece.new(piece1, piece2.position))
	movingPieces.push_back(MovingPiece.new(piece2, piece1.position))
	
func remove_matches() -> bool:
	var foundMatch = find_matches()
	# Wait 0.3 seconds to make the process visually clear
	await get_tree().create_timer(0.3).timeout
	make_specials()
	# Delete flagged pieces
	delete_matches()
	
	return foundMatch
	
func make_specials():
	make_5_in_row_horizontal_special()
	make_5_in_row_verticle_special()
	make_cross_special()
	make_4_in_row_horizontal_special()
	make_4_in_row_verticle_special()
	make_square_special()

func make_5_in_row_horizontal_special():
	for h in height:
		for w in width - 4:
			if check_5_in_row_horizontal(h, w):
				var specialPieceX = w
				var specialPieceY = h
				for k in 5:
					all_pieces[h][w + k].isInSpecialCombo = true
					if (all_pieces[h][w + k].lastRoundMoved > all_pieces[specialPieceY][specialPieceX].lastRoundMoved):
						specialPieceX = w + k
						specialPieceY = h
				spawn_special(specialPieceY, specialPieceX, SpecialPiece.Type.ALL_COLOR)

func check_5_in_row_horizontal(h, w) -> bool: 
	if all_pieces[h][w] is not MatchPiece:
		return false
	var color = all_pieces[h][w].color
	for k in 5:
		if (!all_pieces[h][w + k].isMatched || \
		all_pieces[h][w + k].isInSpecialCombo || \
		all_pieces[h][w + k] is not MatchPiece || \
		all_pieces[h][w + k].color != color):
			return false
	return true
	
func make_5_in_row_verticle_special(): 
	for h in height - 4:
		for w in width:
			if check_5_in_row_verticle(h, w):
				var specialPieceX = w
				var specialPieceY = h
				for k in 5:
					all_pieces[h + k][w].isInSpecialCombo = true
					if (all_pieces[h + k][w].lastRoundMoved > all_pieces[specialPieceY][specialPieceX].lastRoundMoved):
						specialPieceX = w
						specialPieceY = h + k
				spawn_special(specialPieceY, specialPieceX, SpecialPiece.Type.ALL_COLOR)

func check_5_in_row_verticle(h, w) -> bool:
	if all_pieces[h][w] is not MatchPiece:
		return false
	var color = all_pieces[h][w].color
	for k in 5:
		if (!all_pieces[h + k][w].isMatched || \
		all_pieces[h + k][w].isInSpecialCombo || \
		all_pieces[h + k][w] is not MatchPiece || \
		all_pieces[h + k][w].color != color):
			return false
	return true
	
func make_cross_special():
	for h in height:
		for w in width:
			if (all_pieces[h][w] is not MatchPiece):
				continue
			var heightStart = get_cross_height_start(h, w)
			if (heightStart == -1):
				continue
			var widthStart = get_cross_width_start(h, w)
			if (widthStart == -1): 
				continue
				
			var lastMovedH = h
			var lastMovedW = w
			for k in 3:
				all_pieces[h][widthStart+k].isInSpecialCombo = true
				all_pieces[heightStart+k][w].isInSpecialCombo = true
				if (all_pieces[h][widthStart+k].lastRoundMoved > all_pieces[lastMovedH][lastMovedW].lastRoundMoved):
					lastMovedH = h
					lastMovedW = widthStart + k
				if (all_pieces[heightStart+k][w].lastRoundMoved > all_pieces[lastMovedH][lastMovedW].lastRoundMoved):
					lastMovedH = heightStart + k
					lastMovedW = w 
			spawn_special(lastMovedH, lastMovedW, SpecialPiece.Type.CROSS)
				
func get_cross_height_start(h, w) -> int:
	var color = all_pieces[h][w].color
	# check height center
	if (h - 1 >= 0):
		var matchH = check_3_in_row_verticle_special(h -1, w, color)
		if (matchH != -1): return matchH
	if (h - 2 >= 0): 
		var matchH = check_3_in_row_verticle_special(h -2, w, color)
		if (matchH != -1): return matchH
	return check_3_in_row_verticle_special(h, w, color)
		
	# check height right
func check_3_in_row_verticle_special(h, w, color) -> int:
	if (h < height - 2 && \
		all_pieces[h][w] is MatchPiece && \
		all_pieces[h + 1][w] is MatchPiece && \
		all_pieces[h + 2][w] is MatchPiece && \
		all_pieces[h][w].isMatched && \
		all_pieces[h + 1][w].isMatched && \
		all_pieces[h + 2][w].isMatched && \
		!all_pieces[h][w].isInSpecialCombo && \
		!all_pieces[h + 1][w].isInSpecialCombo && \
		!all_pieces[h + 2][w].isInSpecialCombo && \
		all_pieces[h][w].color == color && \
		all_pieces[h + 1][w].color == color && \
		all_pieces[h + 2][w].color == color):
			return h
	return -1

func get_cross_width_start(h, w) -> int:
	var color = all_pieces[h][w].color
	# check height center
	if (w - 1 >= 0):
		var matchW = check_3_in_row_horizontal_special(h, w - 1, color)
		if (matchW != -1): return matchW
	if (w - 2 >= 0): 
		var matchW = check_3_in_row_horizontal_special(h, w - 2, color)
		if (matchW != -1): return matchW
	return check_3_in_row_horizontal_special(h, w, color)
	
func check_3_in_row_horizontal_special(h, w, color) -> int:
	if (w < width - 2 && \
		all_pieces[h][w] is MatchPiece && \
		all_pieces[h][w + 1] is MatchPiece && \
		all_pieces[h][w + 2] is MatchPiece && \
		all_pieces[h][w].isMatched && \
		all_pieces[h][w + 1].isMatched && \
		all_pieces[h][w + 2].isMatched && \
		!all_pieces[h][w].isInSpecialCombo && \
		!all_pieces[h][w + 1].isInSpecialCombo && \
		!all_pieces[h][w + 2].isInSpecialCombo && \
		all_pieces[h][w].color == color && \
		all_pieces[h][w + 1].color == color && \
		all_pieces[h][w + 2].color == color):
			return w
	return -1
	
func make_4_in_row_horizontal_special():
	for h in height:
		for w in width - 3:
			if check_4_in_row_horizontal(h, w):
				var specialPieceX = w
				var specialPieceY = h
				for k in 4:
					all_pieces[h][w + k].isInSpecialCombo = true
					if (all_pieces[h][w + k].lastRoundMoved > all_pieces[specialPieceY][specialPieceX].lastRoundMoved):
						specialPieceX = w + k
						specialPieceY = h
				spawn_special(specialPieceY, specialPieceX, SpecialPiece.Type.LINE_HORIZONTAL)
				
func check_4_in_row_horizontal(h, w) -> bool: 
	if all_pieces[h][w] is not MatchPiece:
		return false
	var color = all_pieces[h][w].color
	for k in 4:
		if (!all_pieces[h][w + k].isMatched || \
		all_pieces[h][w + k].isInSpecialCombo || \
		all_pieces[h][w + k] is not MatchPiece || \
		all_pieces[h][w + k].color != color):
			return false
	return true
	
func make_4_in_row_verticle_special(): 
	for h in height - 3:
		for w in width:
			if check_4_in_row_verticle(h, w):
				var specialPieceX = w
				var specialPieceY = h
				for k in 4:
					all_pieces[h + k][w].isInSpecialCombo = true
					if (all_pieces[h + k][w].lastRoundMoved > all_pieces[specialPieceY][specialPieceX].lastRoundMoved):
						specialPieceX = w
						specialPieceY = h + k
				spawn_special(specialPieceY, specialPieceX, SpecialPiece.Type.LINE_VERTICLE)

func check_4_in_row_verticle(h, w) -> bool:
	if all_pieces[h][w] is not MatchPiece:
		return false
	var color = all_pieces[h][w].color
	for k in 4:
		if (!all_pieces[h + k][w].isMatched || \
		all_pieces[h + k][w].isInSpecialCombo || \
		all_pieces[h + k][w] is not MatchPiece || \
		all_pieces[h + k][w].color != color):
			return false
	return true

func make_square_special():
	for h in height - 1:
		for w in width - 1:
			if (all_pieces[h][w] is MatchPiece && \
			!all_pieces[h][w].isInSpecialCombo && \
			all_pieces[h + 1][w] is MatchPiece && \
			!all_pieces[h + 1][w].isInSpecialCombo && \
			all_pieces[h + 1][w].color == all_pieces[h][w].color && \
			all_pieces[h][w + 1] is MatchPiece && \
			!all_pieces[h][w+ 1].isInSpecialCombo && \
			all_pieces[h][w + 1].color == all_pieces[h][w].color && \
			all_pieces[h + 1][w + 1] is MatchPiece && \
			!all_pieces[h + 1][w + 1].isInSpecialCombo && \
			all_pieces[h + 1][w + 1].color == all_pieces[h][w].color):
				var specialH = h
				var specialW = w
				all_pieces[h][w].isInSpecialCombo = true
				all_pieces[h + 1][w].isInSpecialCombo = true
				all_pieces[h][w + 1].isInSpecialCombo = true
				all_pieces[h + 1][w + 1].isInSpecialCombo = true
				if (all_pieces[h + 1][w].lastRoundMoved > all_pieces[specialH][specialW].lastRoundMoved):
					specialH = h + 1
					specialW = w
				if (all_pieces[h][w + 1].lastRoundMoved > all_pieces[specialH][specialW].lastRoundMoved):
					specialH = h 
					specialW = w + 1
				if (all_pieces[h + 1][w + 1].lastRoundMoved > all_pieces[specialH][specialW].lastRoundMoved):
					specialH = h + 1
					specialW = w + 1
				spawn_special(specialH, specialW, SpecialPiece.Type.FLYER)

func spawn_special(h, w, special: SpecialPiece.Type):
	delete_piece(h,w)
	var piece
	match special: 
		SpecialPiece.Type.ALL_COLOR:
			piece = all_color_special_piece.instantiate()
		SpecialPiece.Type.LINE_HORIZONTAL:
			piece = line_horizontal_piece.instantiate()
		SpecialPiece.Type.LINE_VERTICLE:
			piece = line_verticle_piece.instantiate()
		SpecialPiece.Type.CROSS:
			piece = bomb_piece.instantiate()
		SpecialPiece.Type.FLYER:
			piece = bomb_piece.instantiate()
	add_piece_to_grid(h, w, piece)
	
func find_most_prominent_color() -> String:
	var colorMap = {}
	for h in height:
		for w in width:
			if (all_pieces[h][w] is MatchPiece):
				if colorMap.has(all_pieces[h][w].color):
					colorMap[all_pieces[h][w].color] +=  1
				else: 
					colorMap[all_pieces[h][w].color] = 1
	return colorMap.keys().reduce(compare_color_count.bind(colorMap))

func compare_color_count(a, b, colorMap) -> String:
	if(colorMap.get(a) >= colorMap.get(b)): 
		return a 
	else: 
		return b
	
func trigger_all_color_special(piece, color):
	for h in height:
		for w in width:
			if (all_pieces[h][w] is MatchPiece && all_pieces[h][w].color == color || all_pieces[h][w] == piece):
				delete_piece(h, w)
	
	
