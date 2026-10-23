extends RefCounted
## Strict JSON preflight decoder for imported Research Lab exports.
##
## Godot's JSON parser decodes every number through binary64 and silently keeps the
## last of duplicated keys. The Lab contract forbids both for its exports (decimal
## seeds, signed inertia strings, integers-only fields, no duplicate keys), so the
## importer reads the raw bytes with this small recursive-descent decoder instead:
##   - integer lexemes become exact 64-bit `int`s (out-of-range is an error);
##   - fraction/exponent lexemes become `float` and are flagged (`has_float`);
##   - a duplicated object key is an error;
##   - trailing data, control characters in strings and bad escapes are errors.
## Returns {ok, value, error, has_float}. It is not a general JSON library.

var _text: String
var _i := 0
var _error := ""
var _has_float := false
const MAX_DEPTH := 64

static func decode(text: String) -> Dictionary:
	var parser := new()
	return parser._run(text)

func _run(text: String) -> Dictionary:
	_text = text
	_i = 0
	_skip()
	var value: Variant = _value(0)
	_skip()
	if _error == "" and _i < _text.length():
		_fail("trailing data")
	if _error != "":
		return {"ok": false, "value": null, "error": _error, "has_float": _has_float}
	return {"ok": true, "value": value, "error": "", "has_float": _has_float}

func _fail(message: String) -> void:
	if _error == "":
		_error = "%s at offset %d" % [message, _i]

func _skip() -> void:
	while _i < _text.length() and _text[_i] in [" ", "\t", "\n", "\r"]:
		_i += 1

func _value(depth: int) -> Variant:
	if depth > MAX_DEPTH:
		_fail("nesting too deep")
		return null
	if _i >= _text.length():
		_fail("unexpected end")
		return null
	var c := _text[_i]
	match c:
		"{":
			return _object(depth)
		"[":
			return _array(depth)
		"\"":
			return _string()
		"t":
			return _literal("true", true)
		"f":
			return _literal("false", false)
		"n":
			return _literal("null", null)
	if c == "-" or (c >= "0" and c <= "9"):
		return _number()
	_fail("unexpected character")
	return null

func _literal(word: String, value: Variant) -> Variant:
	if _text.substr(_i, word.length()) != word:
		_fail("bad literal")
		return null
	_i += word.length()
	return value

func _object(depth: int) -> Variant:
	var out := {}
	_i += 1
	_skip()
	if _i < _text.length() and _text[_i] == "}":
		_i += 1
		return out
	while _error == "":
		_skip()
		if _i >= _text.length() or _text[_i] != "\"":
			_fail("expected key")
			return null
		var key: String = _string()
		_skip()
		if _i >= _text.length() or _text[_i] != ":":
			_fail("expected colon")
			return null
		_i += 1
		_skip()
		var value: Variant = _value(depth + 1)
		if out.has(key):
			_fail("duplicate key '%s'" % key)
			return null
		out[key] = value
		_skip()
		if _i < _text.length() and _text[_i] == ",":
			_i += 1
			continue
		if _i < _text.length() and _text[_i] == "}":
			_i += 1
			return out
		_fail("expected , or }")
	return null

func _array(depth: int) -> Variant:
	var out := []
	_i += 1
	_skip()
	if _i < _text.length() and _text[_i] == "]":
		_i += 1
		return out
	while _error == "":
		_skip()
		out.append(_value(depth + 1))
		_skip()
		if _i < _text.length() and _text[_i] == ",":
			_i += 1
			continue
		if _i < _text.length() and _text[_i] == "]":
			_i += 1
			return out
		_fail("expected , or ]")
	return null

func _string() -> String:
	_i += 1
	var out := ""
	while _i < _text.length():
		var c := _text[_i]
		if c == "\"":
			_i += 1
			return out
		if c.unicode_at(0) < 0x20:
			_fail("control character in string")
			return ""
		if c == "\\":
			_i += 1
			if _i >= _text.length():
				break
			var e := _text[_i]
			match e:
				"\"", "\\", "/":
					out += e
				"b":
					out += char(8)
				"f":
					out += char(12)
				"n":
					out += "\n"
				"r":
					out += "\r"
				"t":
					out += "\t"
				"u":
					var hex := _text.substr(_i + 1, 4)
					if hex.length() != 4 or not hex.is_valid_hex_number():
						_fail("bad unicode escape")
						return ""
					out += char(hex.hex_to_int())
					_i += 4
				_:
					_fail("bad escape")
					return ""
			_i += 1
			continue
		out += c
		_i += 1
	_fail("unterminated string")
	return ""

func _number() -> Variant:
	var start := _i
	if _text[_i] == "-":
		_i += 1
	if _i >= _text.length():
		_fail("bad number")
		return null
	if _text[_i] == "0":
		_i += 1
	elif _text[_i] >= "1" and _text[_i] <= "9":
		while _i < _text.length() and _text[_i] >= "0" and _text[_i] <= "9":
			_i += 1
	else:
		_fail("bad number")
		return null
	var is_float := false
	if _i < _text.length() and _text[_i] == ".":
		is_float = true
		_i += 1
		var digits := _i
		while _i < _text.length() and _text[_i] >= "0" and _text[_i] <= "9":
			_i += 1
		if _i == digits:
			_fail("bad fraction")
			return null
	if _i < _text.length() and _text[_i] in ["e", "E"]:
		is_float = true
		_i += 1
		if _i < _text.length() and _text[_i] in ["+", "-"]:
			_i += 1
		var digits := _i
		while _i < _text.length() and _text[_i] >= "0" and _text[_i] <= "9":
			_i += 1
		if _i == digits:
			_fail("bad exponent")
			return null
	var lexeme := _text.substr(start, _i - start)
	if is_float:
		_has_float = true
		return lexeme.to_float()
	# Exact 64-bit integers only; anything longer cannot be represented losslessly.
	var digits_only := lexeme.trim_prefix("-")
	if digits_only.length() > 19 or (digits_only.length() == 19 and digits_only > "9223372036854775807"):
		_fail("integer outside signed 64-bit range")
		return null
	return lexeme.to_int()

## Canonical bytes matching the Lab's `pipeline.canonical`: sorted keys, compact
## separators, ASCII escapes, arrays that are not all-integer sorted by their own
## canonical bytes (records are sets), integer vectors kept in order.
static func canonical(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var keys: Array = (value as Dictionary).keys()
			keys.sort()
			var parts: PackedStringArray = []
			for k: String in keys:
				parts.append(_quote(k) + ":" + canonical(value[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var items: Array = []
			var all_int := true
			for x: Variant in value:
				all_int = all_int and typeof(x) == TYPE_INT
				items.append(canonical(x))
			if not items.is_empty() and not all_int:
				items.sort()
			return "[" + ",".join(PackedStringArray(items)) + "]"
		TYPE_STRING:
			return _quote(value)
		TYPE_INT:
			return str(value)
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_NIL:
			return "null"
	# Floats never appear in a valid export; make the mismatch visible.
	return "<float:%s>" % str(value)

static func _quote(s: String) -> String:
	var out := "\""
	for i in range(s.length()):
		var code := s.unicode_at(i)
		var c := s[i]
		if c == "\"":
			out += "\\\""
		elif c == "\\":
			out += "\\\\"
		elif code == 10:
			out += "\\n"
		elif code == 13:
			out += "\\r"
		elif code == 9:
			out += "\\t"
		elif code == 8:
			out += "\\b"
		elif code == 12:
			out += "\\f"
		elif code < 0x20 or code > 0x7f:
			out += "\\u%04x" % code
		else:
			out += c
	return out + "\""
