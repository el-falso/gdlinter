@tool
class_name GDLinter
extends EditorPlugin

const DockScene := preload("res://addons/gdLinter/UI/Dock.tscn")

const SETTINGS_GDLINT_ENABLED = "debug/settings/Tools/gdlint_enabled"
const SETTINGS_GDLINT_PATH = "debug/settings/Tools/gdlint_path"

var icon_error := EditorInterface.get_editor_theme().get_icon("Error", "EditorIcons")
var color_error: Color = EditorInterface.get_editor_settings()\
		.get_setting("text_editor/theme/highlighting/comment_markers/critical_color")

var icon_error_ignore := EditorInterface.get_editor_theme().get_icon("ErrorWarning", "EditorIcons")
var icon_ignore := EditorInterface.get_editor_theme().get_icon("Warning", "EditorIcons")

var icon_success := EditorInterface.get_editor_theme().get_icon("StatusSuccess", "EditorIcons")
var color_success: Color = EditorInterface.get_editor_settings()\
	.get_setting("text_editor/theme/highlighting/comment_markers/notice_color")

var bottom_panel_button: Button
var highlight_lines: PackedInt32Array
var item_lists: Array[ItemList]
var script_editor: ScriptEditor

var _dock_ui: GDLinterDock
var _is_gdlint_installed: bool
var _ignore: Resource
var _gdlint_path: String


func _enter_tree() -> void:
	if not ProjectSettings.has_setting(SETTINGS_GDLINT_ENABLED):
		ProjectSettings.set_setting(SETTINGS_GDLINT_ENABLED, true)
	if not ProjectSettings.has_setting(SETTINGS_GDLINT_PATH):
		ProjectSettings.set_setting(SETTINGS_GDLINT_PATH, "")

	add_tool_menu_item("Install gdlint with pip", install_gdlint)
  
	var project_gdlint_enabled: bool = ProjectSettings.get_setting(SETTINGS_GDLINT_ENABLED, true)
	
	if(!project_gdlint_enabled):
		var message = "[color=yellow]Loading GDLint Plugin [u]disabled[/u]"
		message += " in [b]Project Settings -> Debug -> Tools[/b][/color]"
		print_rich(message)
		return

	# install the GDLint dock
	_dock_ui = DockScene.instantiate()
	_dock_ui.gd_linter = self
	bottom_panel_button = add_control_to_bottom_panel(_dock_ui, "GDLint")
	
	# connect signal to lint on save
	resource_saved.connect(on_resource_saved)
	
	script_editor = EditorInterface.get_script_editor()
	script_editor.editor_script_changed.connect(_on_editor_script_changed)
	_gdlint_path = get_gdlint_path()
	get_gdlint_version()
	prints("Loading GDLint Plugin success")

# TODO: Reenable again?
# Dunno how highlighting lines in Godot works, since it get removed after a second or so
# So I use this evil workaround straight from hell:
#func _process(_delta: float) -> void:
	#if not get_current_editor():
		#return
	#
	#if not highlight_lines.is_empty():
		#set_line_color(color_error)

func exec(path: String, arguments: PackedStringArray, output: Array=[],read_stderr: bool=false, open_console: bool=false):
	if OS.get_name() == "Windows":
		var args = PackedStringArray(["/C"]) + PackedStringArray([path]) + arguments
		return OS.execute("CMD.exe", args, output, read_stderr, open_console)
	else:
		return OS.execute(path, arguments, output, read_stderr, open_console)

func _on_editor_script_changed(script: Script) -> void:
	_dock_ui.clear_items()
	on_resource_saved(script)


func get_gdlint_version() -> void:
	var output := []
	exec(_gdlint_path, ["--version"], output)
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


func on_resource_saved(resource: Resource) -> void:
	if not resource is GDScript:
		return
	
	_dock_ui.clear_items()
	clear_highlights()
	
	# Show resource path in the GDLint Dock
	_dock_ui.file.text = resource.resource_path
	
	# Execute linting and get its output
	var filepath: String = ProjectSettings.globalize_path(resource.resource_path)
	var gdlint_output: Array = []
	var output_array: PackedStringArray
	var exit_code = exec(_gdlint_path, [filepath], gdlint_output, true)
	if not exit_code == -1:
		var output_string: String = gdlint_output[0]
		output_array = output_string.replace(filepath+":", "Line ").split("\n")
	
		_dock_ui.set_problems_label(_dock_ui.num_problems)
		_dock_ui.set_ignored_problems_label(_dock_ui.num_ignored_problems)
	
	# Workaround until unique name bug is fixed
	# https://github.com/Scony/godot-gdscript-toolkit/issues/284
	# Hope I won't break other stuff with it
	if not output_array.size() or output_array[0] == "Line ":
		printerr("gdLint Error: ", output_array, "\n File can't be linted!")
		return
	
	# When there is no error
	if output_array.size() <= 2:
		bottom_panel_button.add_theme_constant_override(&"icon_max_width", 8)
		bottom_panel_button.icon = icon_success
		return
	
	# When errors are found create buttons in the dock
	for i in output_array.size()-2:
		var regex := RegEx.new()
		regex.compile("\\d+")
		var result := regex.search(output_array[i])
		if result:
			var current_line := int(result.strings[0])-1
			var error := output_array[i].rsplit(":", true, 1)
			if len(error) > 1:
				_dock_ui.create_item(current_line+1, error[1])
				if _dock_ui.is_error_ignored(error[1]):
					continue
				highlight_lines.append(current_line)
	
	_dock_ui.set_problems_label(_dock_ui.num_problems)
	_dock_ui.set_ignored_problems_label(_dock_ui.num_ignored_problems)
	
	# Error, no Ignore
	if _dock_ui.num_problems > 0 and _dock_ui.num_ignored_problems <= 0:
		bottom_panel_button.icon = icon_error
	# no Error, Ignore
	elif _dock_ui.num_problems <= 0 and _dock_ui.num_ignored_problems > 0:
		bottom_panel_button.icon = icon_ignore
	# Error, Ignore
	elif _dock_ui.num_problems > 0 and _dock_ui.num_ignored_problems > 0:
		bottom_panel_button.icon = icon_error_ignore
	else:
		bottom_panel_button.icon = null
	_dock_ui.script_text_editor = EditorInterface.get_script_editor().get_current_editor()


func set_line_color(color: Color) -> void:
	var current_code_editor := get_current_editor()
	if current_code_editor == null:
		return
	
	for line: int in highlight_lines:
		# Skip line if this one is from the old code editor
		if line > current_code_editor.get_line_count()-1:
			continue
		current_code_editor.set_line_background_color(line,
			color.darkened(0.5))


func clear_highlights() -> void:
	set_line_color(Color(0, 0, 0, 0))
	highlight_lines.clear()


func get_current_editor() -> CodeEdit:
	var current_editor := EditorInterface.get_script_editor().get_current_editor()
	if current_editor == null:
		return
	return current_editor.get_base_editor() as CodeEdit


func install_gdlint(python_command := "python"):
	var install_output := []
	OS.execute(python_command, ["-m", "pip", "install", "gdtoolkit==%s.*" % [Engine.get_version_info()["major"]]], install_output)
	if not install_output.is_empty():
		print_rich("[color=green]Install GDLint with pip:[/color]")
		print(install_output[0])


func get_gdlint_path() -> String:
	# First it's searched in $PATH (returning just the name of the binary), and
	# if not found, it's searched in the gdtoolkit package installed via pip or pipx
	if not find_in_path("gdlint").is_empty():
		return "gdlint"
	
	var pip_path := find_pip_gdtoolkit_bin("gdlint")
	if not pip_path.is_empty():
		return pip_path

	if OS.get_name() == "Windows":
		return "gdlint"
	
	# macOS & Linux
	var output := []
	OS.execute("python3", ["-m", "site", "--user-base"], output)
	var python_bin_folder := (output[0] as String).strip_edges().path_join("bin")
	if FileAccess.file_exists(python_bin_folder.path_join("gdlint")):
		return python_bin_folder.path_join("gdlint")
	
	# Linux dirty hardcoded fallback
	if OS.get_name() == "Linux":
		if FileAccess.file_exists("/usr/bin/gdlint"):
			return "/usr/bin/gdlint"
	
	# Global fallback
	return "gdlint"


# Returns the full path of the executable `bin` installed by the gdtoolkit
# package via pip or pipx, or an empty string if not found
func find_pip_gdtoolkit_bin(bin: String) -> String:
	# `pipx runpip <package>` is pip running inside the pipx venv of the package
	var pip_commands: Array[Array] = [
		["pip3", []],
		["pip", []],
		["python3", ["-m", "pip"]],
		["python", ["-m", "pip"]],
		["pipx", ["runpip", "gdtoolkit"]],
	]
	for pip_command: Array in pip_commands:
		if find_in_path(pip_command[0]).is_empty():
			continue
		var args: Array = pip_command[1].duplicate()
		args.append_array(["show", "-f", "gdtoolkit"])
		var output := []
		if OS.execute(pip_command[0], args, output) != 0 or output.is_empty():
			continue
		var path := pip_show_find_bin(output[0], bin)
		if not path.is_empty():
			return path
	return ""


# Returns the full path of the executable `bin` found in $PATH, or an empty
# string if not found.
# Used to check if a command exists before running it, as `OS.execute` prints
# an error on Windows when the executable can't be found
static func find_in_path(bin: String) -> String:
	var is_windows := OS.get_name() == "Windows"
	var extensions: PackedStringArray = [""]
	if is_windows:
		var pathext := OS.get_environment("PATHEXT")
		extensions = (pathext if not pathext.is_empty() else ".COM;.EXE;.BAT;.CMD").split(";", false)

	var separator := ";" if is_windows else ":"
	for folder: String in OS.get_environment("PATH").split(separator, false):
		for extension: String in extensions:
			var path := folder.replace("\\", "/").path_join(bin + extension.to_lower())
			if FileAccess.file_exists(path):
				return path
	return ""


# Given the output of `pip show -f <package>`, returns the full path of the
# executable named `bin` installed by that package, or an empty string if not found
static func pip_show_find_bin(pip_output: String, bin: String) -> String:
	var location := ""
	var file := ""
	# pip on Windows outputs CRLF line endings
	for line: String in pip_output.replace("\r", "").split("\n"):
		if location.is_empty() and line.begins_with("Location:"):
			location = line.trim_prefix("Location:").strip_edges()
		elif file.is_empty() and line.begins_with(" "):
			var candidate := line.strip_edges().replace("\\", "/")
			if candidate.ends_with("/" + bin) or candidate.ends_with("/" + bin + ".exe"):
				file = candidate

	if location.is_empty() or file.is_empty():
		return ""

	var path := location.replace("\\", "/").path_join(file).simplify_path()
	return path if FileAccess.file_exists(path) else ""
