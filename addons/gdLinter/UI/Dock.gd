@tool
class_name GDLinterDock
extends Control

const ERROR_BUTTON = preload("res://addons/gdLinter/UI/ErrorButton.tscn")

var script_text_editor: ScriptEditorBase

@onready var file: Label = %File
@onready var label: Label = %Label
@onready var error_holder: VBoxContainer = %ErrorHolder
@onready var version: Label = %Version
	

func create_error(name: String) -> Button:
	var error: Button = ERROR_BUTTON.instantiate()
	error.text = name
	error_holder.add_child(error)
	return error

func delete_errors() -> void:
	var children := error_holder.get_children()
	for child: Button in children:
		child.queue_free()
