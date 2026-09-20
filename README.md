# Statusify

Statusify is a lightweight, server-side Luau framework for managing status effects on Roblox Humanoid instances.

It provides the infrastructure for registering, applying, stacking, ticking, expiring, clearing, and replicating status effects while leaving gameplay-specific behavior to the developer.

Statusify can be used for effects such as burns, poison, slows, shields, buffs, debuffs, and other temporary or persistent gameplay states.

## Why use Statusify?

Instead of implementing effect lifecycle management repeatedly for every status effect, you register an effect definition once and let Statusify manage its lifecycle.

Statusify provides:

- Effect registration and validation
- Automatic effect lifecycle management
- Optional ticking intervals
- Configurable throttling
- Stack support with multiple stack behaviors
- Duration and expiration management
- Per-Humanoid effect limits
- Lifecycle callbacks
- Optional client replication
- Automatic cleanup of active effects and connections

Statusify is intentionally focused on effect infrastructure, not gameplay presentation or behavior. You decide when effects should be applied and what an effect actually does.

## API

All methods that require multiple parameters use a single consolidated argument table, excluding `self`.

### Module functions

#### New

```lua
New(args: {
	MaxEffectsPerHumanoid: number?,
	ReplicationEvent: RemoteEvent,
}): Types.Statusify?
```

**Constructs the Statusify manager.**

Statusify uses a singleton model, meaning only one manager can exist at a time. Attempting to construct another manager while one already exists will fail.

#### Parameters
- **MaxEffectsPerHumanoid** — The maximum number of unique active effects a Humanoid can have at one time. If omitted, the default value is 3.

- **ReplicationEvent** — The RemoteEvent used for optional server-to-client effect replication. This should be configured before constructing the manager if replication will be used.

##### Example

```lua
local effectManager = Statusify.New({
    MaxEffectsPerHumanoid = 5,
    ReplicationEvent = StatusEffectEvent,
})
```

---

#### GetExistingObject

```lua
GetExistingObject(): Types.Statusify?
```

**Returns the currently existing Statusify manager, or nil if one does not exist.**

This can be used when another part of the server needs access to the manager without retaining the original reference returned by New().

---

### Object Methods

Most methods return a boolean indicating whether the requested operation succeeded.

#### Destroy

```lua
Destroy()
```

**Destroys the current Statusify manager and releases the resources it owns.**

This includes active effects, runtime state, connections, and other resources managed by the framework.

Once destroyed, a new Statusify manager can be constructed.

---

#### RegisterEffect

```lua
RegisterEffect(args: {
	EffectName: string,
	Definition: Types.EffectDefinition,
}): boolean
```

**Registers an effect definition so that it can later be applied to `Humanoid`s.**

An effect must be registered before it can be applied.

You cannot register the same effect name more than once.

Effect names are case-insensitive. For example, "Burn" and "burn" refer to the same effect.

##### Parameters
- **EffectName** — The unique name of the effect.
- **Definition** — The effect definition describing its behavior and lifecycle.

##### Effect definition

The effect definition controls how Statusify manages an effect.

Optional properties are defaulted during registration. Callbacks are not required and remain nil when they are not provided.

See [Defaults](src/server/Defaults.luau) and [Types](src/server/Types.luau) for the complete definitions.

---

###### Properties

**Duration**

```lua
Duration: number?
```

**The amount of time an effect remains active before it expires.**

For stacked effects, the exact duration behavior depends on the configured StackBehavior.

Set the value to math.huge for an effect with no automatic expiration.

---

**Interval**

```lua
Interval: number?
```

**The amount of time between OnTick executions.**

A value less than or equal to 0 disables ticking.

---

**Throttle**

```lua
Throttle: number?
```

**The minimum amount of time that must pass between applications of the same effect to the same `Humanoid`.**

A value less than or equal to 0 disables throttling.

If an application is throttled, the application does not take place.

---

**MaxStacks**

```lua
MaxStacks: number?
```

**The maximum number of stacks the effect can have.**

Attempting to increase the stack count beyond this value will not increase the stack count.

---

**StackBehavior**

**Determines what happens when an effect is applied to a Humanoid that already has that effect.**

Refer to [Stack behavior](#stack-behavior) for more information.

---

**Replicate**

**Controls which lifecycle events are sent to the client.**

Refer to [Replication](#replication) for more information.

---

###### Callbacks

**Every callback receives a context containing information about the effect at that point in its lifecycle.**

**Context**

The callback context provides:

- **Target** — The Humanoid affected by the effect.
- **Stacks** — The current number of stacks.
- **EffectName** — The name of the active effect.
- **StartTime** — The time at which the effect was applied, based on workspace:GetServerTimeNow().
- **ExpireTime** — The time at which the effect is currently scheduled to expire. This value can change during the effect's lifetime.

**OnApply** — Runs when the effect is initially applied to a Humanoid.

**OnTick** — Runs whenever the configured Interval is reached while the effect is active.

**OnRemove** — Runs when the effect is completely removed from a Humanoid.

**OnUpdate** — Runs when an existing effect changes state, like stack being added, stack being removed, and effect being refreshed.

---

#### UnregisterEffect

```lua
UnregisterEffect(args: {
	EffectName: string,
	Terminate: boolean,
}): boolean
```

**Unregisters an effect definition so that it can no longer be applied.**

An effect can later be registered again with a different definition.

##### Parameters

- **EffectName** — The effect definition to unregister.
- **Terminate** — Determines whether currently active instances of the effect should be immediately terminated.

If `Terminate` is `false`, existing active instances are allowed to finish naturally.

**Be careful when unregistering effects with infinite duration. If such an effect is not terminated, it will remain active until its `Humanoid` dies or is removed.**

---

#### ApplyEffect

```lua
ApplyEffect(args: {
	Humanoid: Humanoid,
	EffectName: string,
}): boolean
```

**Applies a registered effect to a `Humanoid`.**

The effect name must correspond to a registered effect definition.

The framework handles the effect's configured stacking behavior, duration, throttling, lifecycle callbacks, runtime scheduling, and replication.

##### Parameters

- **Humanoid** — The `Humanoid` receiving the effect.
- **EffectName** — The name of the registered effect to apply.

---

#### ClearEffect

```lua
ClearEffect(args: {
	Action: "remove" | "removeAll" | "decrement",
	EffectName: string?,
	Humanoid: Humanoid,
}): boolean
```

**Remove an effect status(es) through an optional choice of actions.**

##### Parameters

- **Humanoid** — The `Humanoid` whose effects should be modified.
- **EffectName** — The effect to target. This is optional when using `removeAll`.
- **Action** — Determines how the effect should be cleared.

##### Available actions:

- **"remove"** — Completely removes the specified effect from the Humanoid. The current stack count does not matter.
- **"decrement"** — Removes one stack from the specified effect. If the effect reaches zero stacks, it is completely removed.
- **"removeAll"** — Completely removes every active effect from the Humanoid.

The framework does not decide when an effect should be decremented or removed. The system using Statusify is responsible for deciding when to call these operations.

---

#### GetRegisteredEffect

```lua
GetRegisteredEffect(effectName: string): Types.EffectDefinition?
```

**Returns an immutable copy of the definition of the provided effect name or `nil` if nothing was found.**

The returned definition may differ from the original definition because default values are applied during registration.

---

#### GetActiveEffect

```lua
GetActiveEffect(args: {
	Humanoid: Humanoid,
	EffectName: string,
}): Types.EffectInstance?
```

**Returns an immutable copy of the active effect instance currently running on the specified `Humanoid`, or `nil` if the effect is not active.**

---

#### HasEffect

```lua
HasEffect(args: {
	Humanoid: Humanoid,
	EffectName: string,
}): boolean
```

**Returns whether the specified `Humanoid` currently has the provided effect active.**

---

#### GetNumberOfActiveEffects

```lua
GetNumberOfActiveEffects(humanoid: Humanoid): number
```

**Returns the number of unique active effects currently applied to the Humanoid.**

Stacks are not counted as separate effects.

The returned value cannot exceed `MaxEffectsPerHumanoid`.

## Quick start

### 1. Get the Framework

This repository is configured for [Rojo](https://rojo.space/).

If using Rojo, the project structure will [map](default.project.json) to their respective locations in your Roblox place.

You can also grab it from the Roblox Creator Store.

### 2. Create the manager

```lua
local Statusify = require(pathToStatusify.Api)
local effectManager = Statusify.New({
    MaxNumberPerHumanoid = 5,
    RemoteEvent = nil,
    HumanoidDirectories = nil,
})
```

`Statusify.New()` creates the server-side status-effect manager.

Only one manager/object can exist at a time.

### 3. Register an effect

```lua
local effectName = "burn"

effectManager:RegisterEffect({
    EffectName = effectName,

    Definition = {
        Duration = 10,
        Interval = 1,
        Throttle = 0.5,
        MaxStacks = 3,
        StackBehavior = "refresh",

        OnApply = function(context)
            context.Target:TakeDamage(5)
        end,

        OnTick = function(context)
            context.Target:TakeDamage(5 * context.Stacks)
        end,

        Replicate = {
            Apply = true,
            Tick = false,
            Remove = true,
            Update = true,
        },
    },
})
```

The definition controls the effect's lifecycle, while the callbacks contain the gameplay-specific behavior.

### 4. Apply the effect

```lua
local humanoid = player.Character
    and player.Character:FindFirstChildOfClass("Humanoid")

if humanoid then
    effectManager:ApplyEffect({
        Humanoid = humanoid,
        EffectName = "burn",
    })
end
```

Once applied, Statusify tracks the effect and manages its configured lifecycle.

## Stack behavior

Statusify supports multiple approaches to repeated applications.

### Ignore

```lua
StackBehavior = "ignore"
```

If the effect is already active. The new application does nothing.

### Stack

```lua
StackBehavior = "stack"
```

Each accepted application increases the stack count by one, up to `MaxStacks`, and resets the effect's duration.

### Refresh

```lua
StackBehavior = "refresh"
```

A new application keeps the existing stack count and resets the effect's duration.

Stacks can also be explicitly decremented:

```lua
effectManager:ClearEffect({
    Humanoid = humanoid,
    EffectName = "burn",
    Action = "decrement",
})
```

When the final stack is removed, the effect itself is removed, and OnRemove is executed.

## Built-in lifecycle

Once an effect is applied, Statusify manages the configured lifecycle:

1. Validates the registered effect.
2. Checks application throttling.
3. Creates or updates the active effect.
4. Handles the configured stack behavior.
5. Runs `OnApply` or `OnUpdate` as appropriate.
6. Schedules configured ticks and expiration.
7. Runs `OnTick` at the configured interval.
8. Removes expired effects.
9. Runs `OnRemove` when an effect is completely removed.
10. Sends configured replication events to the client.

The developer remains responsible for deciding when an effect should be applied, decremented, or manually removed.

## Humanoid targeting

Statusify associates effects with `Humanoid` instances rather than `Player` instances.

This allows the same framework to support:

- Players
- NPCs
- Bosses
- Dummies
- Other Humanoid-based entities

The framework does not impose rules about which Humanoids are valid targets. The game using Statusify is responsible for deciding when a Humanoid should receive an effect.

## Replication

Statusify can optionally replicate effect lifecycle information to clients through the configured ReplicationEvent RemoteEvent.

Replication is controlled independently for each effect:

```lua
Replicate = {
    Apply = true, -- Effect becomes active
    Tick = false, -- a configured tick occurs
    Remove = true, -- Effect is completely removed
    Update = true, -- An existing effect changes state, such as through stacking, decrementing, or refreshing
}
```

The client is responsible for deciding what to do with the replicated information.

For example, a client could use an **Apply** event to create a visual effect and an **Update** event to update a stack counter.

Statusify does not provide or enforce client-side presentation.

## Example and tests

A working demonstration is included in the [`example`](example) folder.

Tests are included in the [`tests`](tests) folder.

These are useful starting points for understanding how Statusify is intended to be integrated and for verifying framework behavior.

## Helpful reminders

- Register effect definitions before attempting to apply them.
- Effect names are case-insensitive.
- Effects are associated with `Humanoids` rather than `Player`s.
- Stacks represent multiple applications of the same active effect; they are not separate effect instances.
- `OnApply`, `OnTick`, `OnRemove`, and `OnUpdate` are optional.
- Replication is independently configurable for each lifecycle event.
- Statusify is intended for trusted server-side use. It does not attempt to act as an anti-exploit or security boundary.
- Gameplay systems are responsible for supplying valid inputs and deciding when status effects should be applied or removed.

## License

This project is licensed under the [MIT License](LICENSE).

## Contributing

If you want to extend the framework, the easiest place to start is the server-side source under `src/server` and the demo/test files that show how it is used in practice.
