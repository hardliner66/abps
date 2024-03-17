package main

import "actors"
import "core:fmt"

behaviour :: proc(
	self: ^actors.Actor,
	sys: ^actors.System,
	from: actors.ActorRef,
	msg: actors.Anything,
) {
	switch msg.t {
	case u128:
		v := msg.any.(u128)
		if v >= 10_000_000 {
			actors.stop(sys)
		}
		actors.send(sys, self.ref, from, msg.any.(u128) + 1)
	case string:
		fmt.println("ping received string:", msg.any.(string))
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
