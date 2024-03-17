package main

import "actor"
import "core:c/libc"
import "core:fmt"

MaxMessages :: 10_000_000

Command :: enum {
	Inc,
}

stop_behaviour :: proc(
	self: ^actor.Actor,
	sys: ^actor.System,
	state: ^actor.State,
	from: actor.ActorRef,
	msg: any,
) {
	fmt.println("stopping")
	actor.stop(sys)
}

counting_behaviour :: proc(
	self: ^actor.Actor,
	sys: ^actor.System,
	state: ^actor.State,
	from: actor.ActorRef,
	msg: any,
) {
	switch d in msg {
	case Command:
		data := state^.(u128)
		switch d {
		case .Inc:
			data += 1
		}
		state^ = data
		if data >= MaxMessages {
			actor.become(self, stop_behaviour)
		}
		actor.send(sys, self.ref, from, Command.Inc)
	case u128:
		if d >= MaxMessages {
			actor.become(self, stop_behaviour)
		}
		actor.send(sys, self.ref, from, d + 1)
	case string:
		fmt.println(d)
	}
}

main :: proc() {
	sys := actor.new_system()
	count := actor.spawn(sys, u128(0), counting_behaviour)

	actor.send(sys, count, count, Command.Inc)

	actor.work(sys)

	actor.destroy_system(sys)
}
