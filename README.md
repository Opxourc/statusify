# Statusify

Statusify is a lightweight Luau framework for managing status effects on Roblox humanoids.

It helps you define effects like burn, poison, shield, stun, or buffs, then handle their lifecycle automatically: apply, tick, stack, expire, and clean up.

This project is designed to keep status logic consistent and easy to reuse across a game.

## Why use Statusify?

Instead of writing the same effect logic over and over, you register an effect once and let Statusify manage it.

It gives you:

- automatic effect lifecycles
- optional ticking intervals
- stack support with different stack behaviors
- expiration and cleanup
- replication support for client updates
- per-humanoid effect limits

Statusify is best for gameplay systems, not for rendering visuals. You still decide when effects should be applied and what they should look like in the game.

## Quick start

### 1. Sync the project into Roblox

This repo is set up for Rojo. You can open it in Rojo and sync it into your Roblox place.

The project structure already maps to:

- ServerScriptService.Statusify.Source -> source code
- ReplicatedStorage.Shared.Statusify -> shared files
- example scripts for demo behavior

### 2. Create the manager

```lua
local Statusify = require(script.Parent.Source.Api)

local effectManager = Statusify.New({
    MaxNumberPerHumanoid = 5,
    RemoteEvent = nil,
})
```

`Statusify.New()` creates the main status manager. This framework uses a singleton model so only one manager/object can exist at a time.

### 3. Register an effect

```lua
local effectName = "burn"

effectManager:RegisterEffect(effectName, {
    Duration = 10,
    Interval = 1,
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
})
```

The effect definition includes:

- `Duration`: how long the effect lasts
- `Interval`: how often the effect ticks
- `MaxStacks`: maximum number of stacks allowed
- `StackBehavior`: how reapplying works (`"ignore"`, `"stack"`, or `"refresh"`)
- `OnApply`, `OnTick`, `OnRemove`, `OnUpdate`: callbacks for behavior

Review [Types](src/server/Types.luau) to see the full definition of an effect.

### 4. Apply it to a humanoid

```lua
local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")

if humanoid then
    effectManager:ApplyEffect(humanoid, "burn")
end
```

This adds the effect to that humanoid and starts its runtime.

## Stack behavior

Statusify supports a few ways to handle repeated applications:

- `"ignore"` – do nothing if the effect is already active
- `"stack"` – increase the stack count by 1 up to `MaxStacks` and reset duration
- `"refresh"` – reset the duration and update the effect

This makes it easy to create things like burn, poison, slow, or shield effects without rewriting logic each time.

## Built-in lifecycle

When you apply an effect, Statusify handles the rest:

- checks if the effect is valid
- prevents spam with throttle timing
- tracks the effect by humanoid
- runs `OnApply` when it starts
- runs `OnTick` on the configured interval
- removes the effect when it expires
- runs cleanup callbacks automatically

## Example usage

A working demo is included under the `example` folder and the test scripts under the `tests` folder. These are the best starting points if you want to learn the framework quickly.

## Additional notes

- Use a `Humanoid` as the target, not a `Player`, because many gameplay objects are represented by humanoids.
- Register effects once, then apply them many times.
- Keep `OnApply` and `OnTick` small and focused on gameplay behavior.
- If you want client-side feedback, set `Replicate` flags in your effect definition.

## License

This project is for Roblox game development and is intended to be customized for your own game use.

## Contributing

If you want to extend the framework, the easiest place to start is the server-side source under `src/server` and the demo/test files that show how it is used in practice.
