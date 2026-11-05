class_name InputHelp
## Readable names for actions, following the player's keyboard layout, so the same
## physical key shows as W on QWERTY and Z on AZERTY.


static func label_for(action: StringName) -> String:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventMouseButton:
			return "LMB" if event.button_index == MOUSE_BUTTON_LEFT else "RMB"
		if event is InputEventKey:
			var key: Key = event.physical_keycode
			if DisplayServer.get_name() != "headless":
				key = DisplayServer.keyboard_get_label_from_physical(key)
			return OS.get_keycode_string(key)
	return "?"
