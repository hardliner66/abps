package main

import "actors"
import "core:fmt"

behaviour :: proc(
	self: ^actors.Actor,
	sys: ^actors.System,
	from: actors.ActorRef,
	msg: any,
) {
	switch d in msg {
	case u128:
		if d >= 10_000_000 {
			actors.stop(sys)
		}
		actors.send(sys, self.ref, from, d + 1)
	case string:
		fmt.println(d)
	}
}

main :: proc() {
	sys := actors.new_system()
	ping := actors.spawn(sys, behaviour)
	pong := actors.spawn(sys, behaviour)

	actors.send(sys, ping, pong, "test")
	// actors.send(sys, ping, pong, u128(0))

	actors.work(sys)
}
