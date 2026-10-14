class_name Uuid
extends RefCounted
## Identifiants UUID version 4 (aléatoires), au format attendu par le back :
## "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".


static func v4() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40     # version 4
	bytes[8] = (bytes[8] & 0x3f) | 0x80     # variante RFC 4122
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
