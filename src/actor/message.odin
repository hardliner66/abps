package actor


Message :: struct {
	to:   ActorRef,
	from: ActorRef,
	msg:  Anything,
}