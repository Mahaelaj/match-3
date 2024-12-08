class_name MovingPiece
extends  Node

var piece: Piece
var destination: Vector2
	
func _init(piece, destination):
	self.piece = piece
	self.destination = destination

func move(speed, delta):
	if (piece.position == destination):
		return true
	piece.position = piece.position.move_toward(destination, delta * speed)
	return false
