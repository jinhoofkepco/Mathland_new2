class_name AppShell
extends Control

@onready var route_host: Control = %RouteHost

func _ready() -> void:
	set_process_unhandled_input(true)
