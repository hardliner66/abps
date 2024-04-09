# ABPS - Actor Based Programming System

## What it currently is

An experimental actor framework which covers some of the basics.

### Current Features
- Configurable
- M:N Multitasking
- Struct based actors
  - Any struct containing a handle function with the appropriate signature can be used as an actor
  - Fields on the struct can be used as state
- Spawning of actors
- Sending & receiving of messages
- Sending of errors to parent actors
- Send anything as message
- Simple message matching api
  - Matching a message marks it as read
  - Unread messages get logged

## What I want it to be in the future

A programming language that is based on the actor model, running on a custom runtime in order to allow for repl
based development and debugging.

### Planned Features
- Work stealing
- Actor based programming language
- Debugging features
  - Create/Modify/Delete Actors at runtime
  - Send messages to actors from the debugger
  - Inspect the state of actors
  - Allow remote debugging for clusters
- REPL

## What it's not supposed to be

### No general purpose actor framework
It's not supposed to be a general purpose actor framework, even tho right now it can be used like one.
I try to keep it that way, so others can use it for their projects as well, but if that gets in the way of
implementing some of the features needed to reach the goal, I will drop that use case in favor of the end goal.

### No guarantees for production readiness
For now, there is no goal in making this production ready. There might be changes to anything, including but not
limited to the API, the behavior, dependencies used, etc. **Use at your own risk**

That also means, there is no guarantee for support. If something breaks or doesn't work you can still create issues,
but I reserve the right to decide if fixing an issue is worth doing for what I want to acheive.
So if you want a feature that doesn't fit my vision, you can add a PR and if it doesn't hurt maintanability
or my ability to move forward, I might merge it.
