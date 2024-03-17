package uuid

import "core:crypto"
import "core:io"
import "core:mem"

UUID_SIZE :: 16
UUID     :: distinct [UUID_SIZE]byte

generate :: proc() -> (u: UUID) #no_bounds_check {
	crypto.rand_bytes(u[:])

	u[6] = (u[6] & 0x0f) | (4 << 4)
	u[8] = (u[8]&(0xff>>2) | (0x02 << 6))
	return u
}

to_string :: proc(dst: []byte, u: UUID) #no_bounds_check {
	u := u
	assert(len(dst) >= 36, "dst not big enough for UUID")

	hex(dst[0:8], u[0:4])
	dst[8] = '-'
	hex(dst[9:13], u[4:6])
	dst[13] = '-'
	hex(dst[14:18], u[6:8])
	dst[18] = '-'
	hex(dst[19:23], u[8:10])
	dst[23] = '-'
	hex(dst[24:], u[10:])
}

clone_to_string :: proc(u: UUID, allocator := context.allocator) -> (str: string, err: mem.Allocator_Error) {
	buf := make([]byte, 36, allocator) or_return
	to_string(buf, u)
	str = string(buf)
	return
}

write :: proc(dst: io.Writer, u: UUID, n_written: ^int = nil) -> (int, io.Error) {
	buf: [36]byte
	to_string(buf[:], u)
	return io.write(dst, buf[:], n_written)
}

@(private)
HEXTABLE := [16]byte {
	'0', '1', '2', '3',
	'4', '5', '6', '7',
	'8', '9', 'a', 'b',
	'c', 'd', 'e', 'f',
}

@(private)
hex :: proc(dst, src: []byte) #no_bounds_check {
	i := 0
	for v in src {
		dst[i]   = HEXTABLE[v>>4]
		dst[i+1] = HEXTABLE[v&0x0f]
		i+=2
	}
}