@tool
class_name GDLinter
extends EditorPlugin

const DockScene := preload("res://addons/gdLinter/UI/Dock.tscn")

const SETTINGS_GDLINT_ENABLED = "debug/settings/Tools/gdlint_enabled"
const SETTINGS_GDLINT_PATH = "debug/settings/Tools/gdlint_path"
const SETTINGS_PYTHON_PATH = "debug/settings/Tools/python_path"

const GDLINT_PYTHON_MODULE = "gdtoolkit.linter"

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
var _ignore: Resource

var _gdlint_path: String = ""
var _gdlint_version: String = ""

func get_python_path() -> String:
	return str(ProjectSettings.get_setting(SETTINGS_PYTHON_PATH, "py" if (OS.get_name() == "Windows") else "python3")).strip()

func get_current_gdlint_path() -> String:
	return _gdlint_path

func get_current_gdlint_version() -> String:
	return _gdlint_version

func is_current_gdlint_installed() -> bool:
	return get_current_gdlint_version().is_empty()


func update_gdlint_info() -> void:
	_gdlint_path = _get_gdlint_command()
	_gdlint_version = ""
	
	if get_current_gdlint_path().is_empty():
		return
	
	_gdlint_version = _get_gdlint_command_version(get_current_gdlint_path())

	# couldn't this be handled in the doc's code instead of over here?
	if is_current_gdlint_installed():
		_dock_ui.version.text = "Using gdlint %s" % get_current_gdlint_version()
	else:
		_dock_ui.version.text = "gdlint not found!"

func _get_gdlint_command_version(command:String) -> String:
	var output := []
	exec(command, ["--version"], output)
	if output.is_empty():
		return ""
	var ver_str := "".join(output).strip()
	if ver_str.to_lower().starts_with("gdlint"):
		ver_str = ver_str.slice("gdlint".length())
	return ver_str.strip()
	
func _get_gdlint_command(allow_file_ui := false) -> String:
	var project_gdlint_path: String = ProjectSettings.get_setting(SETTINGS_GDLINT_PATH, "").strip()
	
	if not project_gdlint_path.is_empty():
		return project_gdlint_path

	# The stock ways that one would call gdlint
	if OS.get_name() == "Windows":
		if not _get_gdlint_command_version("gdlint").is_empty()
			return "gdlint"
	
	if not get_python_path().is_empty()::
		var output := []
		exec(get_python_path(), ["-m", "site", "--user-base"], output)
		var python_bin_folder := (output[0] as String).strip_edges().path_join("bin")
		var gdlint_exe := python_bin_folder.path_join("gdlint")
		if FileAccess.file_exists(gdlint_exe) and not _get_gdlint_command_version(gdlint_exe).is_empty():
			return gdlint_exe

		# Attempt to make the command a call to the python module directly (may not work since the arguments are included in the command name;
		# and making that happen is alot of refactioring for a single possible case)
		var python_call_module_hack := "%s -m %s" % [get_python_path(), GDLINT_PYTHON_MODULE]
		if not _get_gdlint_command_version(python_call_module_hack).is_empty():
			return python_call_module_hack

	# Alright then, hard way it is...

	# Linux dirty hardcoded fallback
	if OS.get_name() == "Linux" or OS.get_name().ends_with("BSD"):
		if FileAccess.file_exists("/usr/bin/gdlint") and not _get_gdlint_command_version("/usr/bin/gdlint").is_empty():
			return "/usr/bin/gdlint"

	if allow_file_ui:
		var dia := EditorFileDialog()
		dia.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		dia.access = EditorFileDialog.ACCESS_FILESYSTEM
		dia.dialog_hide_on_ok = true
		dia.show_hidden_files = true
		dia.title = "Find gdlint executable"
		dia.cancel_button_text = "Try default ('gdlint')"
		dia.popup_file_dialog()
		while dia.visible:
			await dia.visibility_changed
		# The user would never lie to us
		if not dia.current_file.is_empty():
			reutrn dia.current_file

	# Global fallback
	return "gdlint"


func _enter_tree() -> void:
	if not ProjectSettings.has_setting(SETTINGS_GDLINT_ENABLED):
		ProjectSettings.set_setting(SETTINGS_GDLINT_ENABLED, true)
	if not ProjectSettings.has_setting(SETTINGS_GDLINT_PATH):
		ProjectSettings.set_setting(SETTINGS_GDLINT_PATH, "")
	if not ProjectSettings.has_setting(SETTINGS_PYTHON_PATH):
		ProjectSettings.set_setting(SETTINGS_PYTHON_PATH, "py" if (OS.get_name() == "Windows") else "python3")

	add_tool_menu_item("Install gdlint with pip", install_gdlint)
	add_tool_menu_item("Re-find gdlint executable", update_gdlint_info.bind(true))
  
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
	update_gdlint_info()
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

# arguments accepts both Arrays and PackedStringArrays
func exec(path: String, arguments: Variant, output: Array=[],read_stderr: bool=false, open_console: bool=false):
	if OS.get_name() == "Windows":
		var args = PackedStringArray(["/C"]) + PackedStringArray([path]) + arguments
		OS.execute("CMD.exe", args, output, read_stderr, open_console)
	else:
		OS.execute(path, arguments, output, read_stderr, open_console)

func _on_editor_script_changed(script: Script) -> void:
	_dock_ui.clear_items()
	on_resource_saved(script)


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
	var exit_code = exec(get_gdlint_path(), [filepath], gdlint_output, true)
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


func install_gdlint(python_command := ""):
	if python_command.is_empty():
		python_command = get_python_path()
	var install_output := []
	exec(python_command, ["-m", "pip", "--upgrade", "install", "gdtoolkit==%s.*" % [Engine.get_version_info()["major"]]], install_output)
	if not install_output.is_empty():
		print_rich("[color=green]Install GDLint with pip:[/color]")
		print(install_output[0])
