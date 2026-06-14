extends TileMapLayer

func _ready() -> void:
	var used_cells := get_used_cells()
	var tile_set_resource: TileSet = tile_set
	if tile_set_resource == null:
		return
	
	var decoration_array : Array = []
	
	# loop qua tat ca source
	for source_index in range(tile_set_resource.get_source_count()):
		var source_id := tile_set_resource.get_source_id(source_index)
		var source := tile_set_resource.get_source(source_id)
		
		if source is TileSetAtlasSource:
			
			for tile_id in range(source.get_tiles_count()):
				var atlas_coords = source.get_tile_id(tile_id)
				var tile_data : TileData = source.get_tile_data(atlas_coords, 0)
				if tile_data == null:
					continue
				var tile_type = tile_data.get_custom_data("type")
				
				if tile_type == "deco":
					decoration_array.append({
						"source_id": source_id,
						"coords": atlas_coords
					})
	if decoration_array.is_empty():
		return
			
	for cell in used_cells:
		var cell_data : TileData = get_cell_tile_data(cell)
		if cell_data == null:
			continue
		var cell_type : String = cell_data.get_custom_data("type")
		
		if cell_type == "upward":
			_randomize_decoration(Vector2i(cell.x, cell.y - 1), decoration_array)
			
			
func _randomize_decoration(cell : Vector2i, decor_array : Array) -> void:
	if get_cell_source_id(cell) != -1:
		return

	var prob = randf_range(0.0, 1.0)
	
	if prob > 0.7:
		return
		
	var decor = decor_array.pick_random()
	
	set_cell(cell, decor["source_id"], decor["coords"])
