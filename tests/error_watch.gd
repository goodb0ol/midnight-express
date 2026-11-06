extends Logger
## Collects every engine and script error, so one that scrolls past fails its test. Called
## from any thread, hence the lock. FAIL lines are the runner's own report of a failed check.

var _lock := Mutex.new()
var _lines: Array[String] = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING or code.begins_with("FAIL") or rationale.begins_with("FAIL"):
		return
	_lock.lock()
	_lines.append("%s %s at %s:%d in %s" % [code, rationale, file, line, function])
	_lock.unlock()


## Everything logged since the last call.
func take() -> Array[String]:
	_lock.lock()
	var lines := _lines
	_lines = []
	_lock.unlock()
	return lines
