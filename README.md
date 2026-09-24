# Statusify

Statusify is a server-side Luau framework for managing temporary gameplay effects on Roblox Humanoids.

The library is built around a simple pattern:

1. register an effect definition
2. apply it to a Humanoid
3. let Statusify manage the lifecycle, ticks, duration, stacks, and cleanup

This project is intentionally infrastructure-focused. It does not decide visual presentation or gameplay rules for you; it manages the effect lifecycle in a structured and reusable way.

## Source-level overview

The current implementation is split across the following files:

- `src/Api.luau` — public API surface and object lifecycle
- `src/Types.luau` — type contracts for definitions, instances, context, and the manager
- `src/Defaults.luau` — default values for effect definitions and constructor arguments
- `src/Effects.luau` — stack mutation, callback execution, and add/remove behavior
- `src/Runtime.luau` — runtime loop for ticking and expiration checks
- `src/Replication.luau` — server-to-client replication logic
- `src/Threads.luau` — per-effect callback thread tracking
- `src/Watcher.luau` — humanoid lifecycle cleanup
- `src/Utilities.luau` — name normalization and context helpers

## How to grab it

There's three ways you can use this framework for your Roblox place.

1. This framework is already set up for [Rojo](https://rojo.space/). You can use Git to pull to your local machine and quickly sync to a Roblox place and start running it.

2. You can grab it from [Wally](https://wally.run/), the package manager for Roblox development. Probably the safest and most convient option if you're already using Rojo.

3. Grab it from the Roblox Creator Hub. Note that the framework will come in as a package so you can optionally auto-update to the latest version or roll back when needed.

## Constructor

The public manager is created with `Statusify.new(...)`.

```lua
local Statusify = require(script.Parent.Source.Api)

local statusify = Statusify.new({
    MaxEffectsPerHumanoid = 5,
    ReplicationEvent = nil,
})
```

### Arguments

```lua
Statusify.new(args: {
    MaxEffectsPerHumanoid: number?,
    ReplicationEvent: RemoteEvent?,
})
```

- `MaxEffectsPerHumanoid`: maximum number of active effects per Humanoid. Defaults to `3`.
- `ReplicationEvent`: optional RemoteEvent used for effect replication. If omitted, no replication messages are sent even if `Replicate` flags are enabled.

## EffectDefinition

`EffectDefinition` is the core configuration object used when registering a status effect.

```lua
export type EffectDefinition = {
    Duration: number?,
    Interval: number?,
    Replicate: {
        Apply: boolean?,
        Tick: boolean?,
        Remove: boolean?,
        Update: boolean?,
    }?,
    Throttle: number?,
    MaxStacks: number?,
    StackBehavior: StackBehavior?,

    OnTick: ((context: EffectContext) -> ())?,
    OnApply: ((context: EffectContext) -> ())?,
    OnRemove: ((context: EffectContext) -> ())?,
    OnUpdate: ((context: EffectContext) -> ())?,
}
```

### Default values

These values are defined in `src/server/Defaults.luau` and are applied when omitted:

```lua
Duration = 5
Interval = 1
MaxStacks = math.huge
StackBehavior = "stack_refresh"
Throttle = 0.25
Replicate = {
    Apply = true,
    Tick = true,
    Remove = true,
    Update = true,
}
```

### Definition properties

#### Duration

```lua
Duration: number?
```

How long a single stack remains active before expiration. This is used as the effect's expiry timeline.

#### Interval

```lua
Interval: number?
```

How often `OnTick` should run. If this value is `<= 0`, ticking is effectively disabled.

#### Throttle

```lua
Throttle: number?
```

Minimum time required before the same effect can be applied again to the same Humanoid. This is checked using `NextAvailableApplyTime`.

#### MaxStacks

```lua
MaxStacks: number?
```

Maximum stack count allowed for the effect. `Effects.MutateStack` clamps the stack value to this limit.

#### StackBehavior

```lua
StackBehavior: "refresh" | "stack" | "ignore" | "stack_refresh"
```

Controls how repeated application behaves when the effect is already active.

Supported values:

- `"ignore"` — do nothing when the effect is re-applied
- `"stack"` — add one stack, do not reset duration
- `"refresh"` — reset the duration, do not add a stack
- `"stack_refresh"` — add one stack and reset the duration

This is enforced in `Api.Apply`.

#### Replicate

```lua
Replicate = {
    Apply = true,
    Tick = true,
    Remove = true,
    Update = true,
}
```

If set, each lifecycle event can be replicated to clients when that event occurs.

The actual replication check happens in `src/server/Replication.luau` and only sends messages if:

- a `ReplicationEvent` was created at manager construction time
- the relevant `Replicate` flag is true
- the event message matches the lifecycle step

### Callback contract

Callback signatures are defined under `Types.EffectDefinition`:

```lua
OnTick: ((context: EffectContext) -> ())?,
OnApply: ((context: EffectContext) -> ())?,
OnRemove: ((context: EffectContext) -> ())?,
OnUpdate: ((context: EffectContext) -> ())?,
```

`EffectContext` looks like this:

```lua
export type EffectContext = {
    Target: Humanoid,
    Stacks: number,
    EffectName: string,
    StartTime: number,
    ExpireTime: number,
}
```

This is created by `Utilities.createContext(...)` and passed into each callback as `context`.

#### Callbacks and when they run

- `OnApply`: first time the effect is added to a Humanoid
- `OnTick`: each interval while active
- `OnUpdate`: when the effect is updated through stack mutation or reapplication
- `OnRemove`: when the effect is removed or expires

These are invoked through `Effects.RunCallback`, which wraps each callback in `xpcall` and logs errors without crashing the task.

## Public API

All public methods take an argument table and operate as instance methods. The API is defined in `src/server/Api.luau` and typed in `src/server/Types.luau`.

### Register

```lua
statusify:Register({
    EffectName = "burn",
    Definition = {
        Duration = 10,
        Interval = 1,
        MaxStacks = 3,
        StackBehavior = "stack_refresh",

        OnApply = function(context)
            context.Target:TakeDamage(5)
        end,

        OnTick = function(context)
            context.Target:TakeDamage(5 * context.Stacks)
        end,
    },
})
```

Signature:

```lua
Register(self: Statusify, args: {
    EffectName: string,
    Definition: EffectDefinition,
})
```

Behavior:

- normalizes the effect name to lowercase
- rejects duplicate registration names
- fills missing fields with defaults
- normalizes the `Replicate` table
- stores the effect definition under `_registeredEffects`

### Unregister

```lua
statusify:Unregister({
    EffectName = "burn",
    Terminate = true,
})
```

Signature:

```lua
Unregister(self: Statusify, args: {
    EffectName: string,
    Terminate: boolean,
})
```

Behavior:

- removes the effect from the registry
- if `Terminate == true`, removes all active instances of that effect from every Humanoid
- if `Terminate == false`, active effects are left alone and may expire naturally

### Apply

```lua
statusify:Apply({
    Humanoid = humanoid,
    EffectName = "burn",
})
```

Signature:

```lua
Apply(self: Statusify, args: {
    Humanoid: Humanoid,
    EffectName: string,
})
```

Behavior:

- checks whether the effect is registered
- resolves the active effect for that Humanoid
- if no active effect exists, creates one and calls `OnApply`
- if the effect already exists, applies stack/refresh behavior based on `StackBehavior`
- updates `NextAvailableApplyTime` using the `Throttle`
- calls `_Replicate({ Message = "update" })` and `_RunCallback({ Message = "update" })` for reapplication changes

Effects are visible as `EffectInstance` values internally:

```lua
export type EffectInstance = {
    Definition: EffectDefinition,
    Name: string,
    Stacks: number,
    StartTime: number,
    ExpireTime: number,
    NextTickTime: number,
    NextAvailableApplyTime: number,
}
```

### Remove

```lua
statusify:Remove({
    Humanoid = humanoid,
    Action = "effect",
    EffectName = "burn",
})
```

Signature:

```lua
Remove(self: Statusify, args: {
    Action: "effect" | "all" | "decrement",
    EffectName: string?,
    Humanoid: Humanoid,
})
```

Action behavior:

- `"effect"` — remove the named effect from a Humanoid
- `"all"` — remove every active effect from that Humanoid
- `"decrement"` — decrement stack count by 1; remove effect automatically when it reaches zero

This is the removal API used by runtime expiry and manual cleanup.

### GetRegistered

```lua
local definition = statusify:GetRegistered("burn")
```

Signature:

```lua
GetRegistered(self: Statusify, effectName: string): EffectDefinition?
```

Returns the effect definition currently registered under that name.

### GetActive

```lua
local effect = statusify:GetActive({
    Humanoid = humanoid,
    EffectName = "burn",
})
```

Signature:

```lua
GetActive(self: Statusify, args: {
    Humanoid: Humanoid,
    EffectName: string,
}): EffectInstance?
```

Returns the currently active effect instance for the Humanoid and effect name.

### GetActiveCount

```lua
local count = statusify:GetActiveCount(humanoid)
```

Signature:

```lua
GetActiveCount(self: Statusify, humanoid: Humanoid): number
```

Counts all active effects for a Humanoid.

### Destroy

```lua
statusify:Destroy()
```

Signature:

```lua
Destroy(self: Statusify) -> nil
```

This tears down the manager, destroys runtime state, disconnects watchers, cancels threads, and clears active runtime data.

## Runtime flow and lifecycle semantics

The lifecycle is driven by a runtime loop and a set of internal helper functions:

- `Effects.Add` adds a new active effect and triggers `apply` replication/callback
- `Effects.MutateStack` clamps stack counts and removes the effect if it reaches zero
- `Effects.RunCallback` runs `OnApply`, `OnTick`, `OnUpdate`, and `OnRemove` callbacks in spawned threads
- `Runtime.Create` / `Runtime.Destroy` manage the continuous expiration/tick loop
- `Watcher.Create` / `Watcher.Destroy` clean up effects when a Humanoid is removed or dies
- `Replication.Replicate` sends lifecycle events only if enabled and a replication event exists

## Example

```lua
local Statusify = require(game.ServerScriptService.Statusify.Source.Api)

local statusify = Statusify.new({
    MaxEffectsPerHumanoid = 5,
    ReplicationEvent = nil,
})

statusify:Register({
    EffectName = "slow",
    Definition = {
        Duration = 6,
        Interval = 1,
        Throttle = 0.25,
        MaxStacks = 2,
        StackBehavior = "stack",

        OnApply = function(context)
            print(context.Target.Name .. " is now slowed")
        end,

        OnTick = function(context)
            print("Slow tick", context.Stacks)
        end,

        OnRemove = function(context)
            print(context.Target.Name .. " is no longer slowed")
        end,
    },
})

local humanoid = workspace.TestHumanoid
statusify:Apply({
    Humanoid = humanoid,
    EffectName = "slow",
})

statusify:Remove({
    Humanoid = humanoid,
    Action = "decrement",
    EffectName = "slow",
})
```

## Notes for source-based use

- Effect names are normalized internally, so casing is not significant.
- The manager is object-based, and methods are called as instance methods: `statusify:Register(...)`.
- The implementation distinguishes between public API methods and internal helper methods beginning with underscores, such as `_AddEffect`, `_Replicate`, and `_RunCallback`.
- `Runtime` and `Watcher` are responsible for the framework lifecycle, while your game code supplies the actual gameplay side effects in callbacks.

## Summary

Statusify is a structured status-effect runtime that centralizes:

- effect registration
- stack rules
- lifetime management
- tick scheduling
- replication
- callback execution
- cleanup logic

It is most useful when you want consistent, reusable status effects without re-implementing the same lifecycle logic in every system.

The returned definition may differ from the original definition because default values are applied during registration.

## License

This project is licensed under the [MIT License](LICENSE).

## Contributing

Review [CONTRIBUTING](CONTRIBUTING.md) for more information.