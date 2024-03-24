package actor

Anything :: struct {
	data: any,
	ptr:  rawptr,
}

new_anything :: proc(value: $T) -> Anything {
	p := new(T)
	p^ = value
	return Anything{p^, p}
}

free_anything :: proc(any: Anything) {
	free(any.ptr)
}

Any :: union {
	// booleans
	bool,
	b8,
	b16,
	b32,
	b64,

	// integers
	int,
	i8,
	i16,
	i32,
	i64,
	i128,
	uint,
	u8,
	u16,
	u32,
	u64,
	u128,
	uintptr,

	// endian specific integers
	// little endian
	i16le,
	i32le,
	i64le,
	i128le,
	u16le,
	u32le,
	u64le,
	u128le,
	// big endian
	i16be,
	i32be,
	i64be,
	i128be,
	u16be,
	u32be,
	u64be,
	u128be,
	// floating point numbers
	f16,
	f32,
	f64,

	// endian specific floating point numbers
	// little endian
	f16le,
	f32le,
	f64le,
	// big endian
	f16be,
	f32be,
	f64be,
	// complex numbers
	complex32,
	complex64,
	complex128,
	// quaternion numbers
	quaternion64,
	quaternion128,
	quaternion256,
	// signed 32 bit integer
	// represents a Unicode code point
	// is a distinct type to `i32`
	rune,
	// strings
	string,
	cstring,

	// raw pointer type
	rawptr,

	// runtime type information specific type
	typeid,

	// custom types
	ActorRef,

	// containers
	[dynamic]Any,
	map[string]Any,
}