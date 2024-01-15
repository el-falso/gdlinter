@tool
extends EditorPlugin

const DockScene := preload("res://addons/gdLinter/UI/Dock.tscn")

var icon_error := EditorInterface.get_editor_theme().get_icon("Error", "EditorIcons")
var color_error: Color = EditorInterface.get_editor_settings()\
		.get_setting("text_editor/theme/highlighting/comment_markers/critical_color")

var icon_success := EditorInterface.get_editor_theme().get_icon("StatusSuccess", "EditorIcons")
var color_success: Color = EditorInterface.get_editor_settings()\
	.get_setting("text_editor/theme/highlighting/comment_markers/notice_color")

var bottom_panel_button: Button
var highlight_lines: PackedInt32Array
var item_lists: Array[ItemList]

var _dock_ui: GDLinterDock
var _is_gdlint_installed: bool


func _enter_tree() -> void:
	# install the GDLint dock
	_dock_ui = DockScene.instantiate()
	bottom_panel_button = add_control_to_bottom_panel(_dock_ui, "GDLint")
	
	# connect signal to lint on save
	resource_saved.connect(on_resource_saved)
	await get_tree().create_timer(1.0).timeout # Workaround so the script editor gets loaded
	var current_open_script = load(ProjectSettings.globalize_path(
				EditorInterface.get_script_editor().get_current_script().resource_path)
		) as Resource
	on_resource_saved(current_open_script)
	
	var script_editor := EditorInterface.get_script_editor()
	script_editor.editor_script_changed.connect(_on_editor_script_changed)
	get_gdlint_version()
	
	get_item_list(script_editor)

	prints("Loading GDLint Plugin success")


# Dunno how highlighting lines in Godot works, since it get removed after a second or so
# So I use this evil workaround straight from hell:
func _process(_delta: float) -> void:
	if not highlight_lines.is_empty():
		set_line_color(color_error)


func _on_editor_script_changed(_script: Script) -> void:
	var current_open_script = load(ProjectSettings.globalize_path(
			EditorInterface.get_script_editor().get_current_script().resource_path)) as Resource
	on_resource_saved(current_open_script)


func get_gdlint_version() -> void:
	var output := []
	OS.execute("gdlint", ["--version"], output)
	_is_gdlint_installed = true if not output[0].is_empty() else false
	if _is_gdlint_installed:
		_dock_ui.version.text = "Using %s" % output[0]
	else:
		_dock_ui.version.text = "gdlint not found!"


func _exit_tree() -> void:
	if is_instance_valid(_dock_ui):
		remove_control_from_bottom_panel(_dock_ui)
		_dock_ui.free()
	
	if Engine.get_version_info().hex >= 0x40201:
		prints("Unload GDLint Plugin success")


func on_resource_saved(resource: Resource):
	_dock_ui.delete_errors()
	clear_highlights()
	
	# Show resource path in the GDLint Dock
	_dock_ui.file.text = resource.resource_path
	
	# Execute linting and get its output
	var filepath: String = ProjectSettings.globalize_path(resource.resource_path)
	var gdlint_output: Array = []
	var output_array: PackedStringArray
	var exit_code = OS.execute("gdlint", [filepath], gdlint_output, true)
	if not exit_code == -1:
		var output_string: String = gdlint_output[0]
		output_array = output_string.replace(filepath+":", "Line ").split("\n")
	
	# When there is no error
	if output_array.size() <= 2:
		print(output_array)
		_dock_ui.label.text = output_array[0]
		_dock_ui.label.modulate = color_success
		bottom_panel_button.icon = icon_success
		return
	
	# When errors are found create buttons in the dock
	for i in output_array.size()-2:
		var regex := RegEx.new()
		regex.compile("\\d+")
		var result := regex.search(output_array[i])
		var current_line := int(result.strings[0])-1
		highlight_lines.append(current_line)
		
		var button: Button = _dock_ui.create_error(output_array[i])
		button.pressed.connect(go_to_line.bind(current_line))
		
	_dock_ui.label.text = output_array[output_array.size()-2]
	_dock_ui.label.modulate = Color(255, 255, 255)
	bottom_panel_button.icon = icon_error
	_dock_ui.script_text_editor = EditorInterface.get_script_editor().get_current_editor()


func go_to_line(line: int) -> void:
	var tab_container := _dock_ui.script_text_editor.get_parent() as TabContainer
	
	for index in tab_container.get_child_count():
		if tab_container.get_child(index) == _dock_ui.script_text_editor:
			item_lists[0].select(index)
			item_lists[0].item_selected.emit(index)
	
	var current_code_editor := get_current_editor()
	current_code_editor.set_caret_line(line)


func get_item_list(node: Node) -> void:
	for child: Node in node.get_children():
		if not child is ItemList:
			if child is Window:
				break
			get_item_list(child)
		else:
			item_lists.append(child)


func set_line_color(color: Color) -> void:
	for line: int in highlight_lines:
		var current_code_editor := get_current_editor()
		current_code_editor.set_line_background_color(line,
			color.darkened(0.5))


func clear_highlights() -> void:
	set_line_color(Color(0, 0, 0, 0))
	highlight_lines.clear()


func get_current_editor() -> CodeEdit:
	return EditorInterface.get_script_editor().get_current_editor().get_base_editor() as CodeEdit
