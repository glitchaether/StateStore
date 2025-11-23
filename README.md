# StateStore

<div align="center">
	<a href="https://wally.run/package/glitchaether/statestore">
		<img src="https://img.shields.io/badge/wally-v0.0.1-ad4646" alt="Wally Version" />
	</a>
	<a href="https://github.com/glitchaether/StateStore/blob/main/LICENSE">
		<img src="https://img.shields.io/badge/license-MIT-blue" alt="License" />
	</a>
</div>

<div align="center">
	<h3>
		<a href="https://glitchaether.github.io/modules/StateStore">Documentation Soon</a>
	</h3>
</div>

---

**StateStore** is a predictable state container for Roblox, inspired by Redux. It helps you write applications that behave consistently, run in different environments (client/server), and are easy to test.

It serves as a **Single Source of Truth** for your game data, handling replication, middleware, and state history automatically.

## Features

* **Immutable State:** Prevents accidental data mutations using `table.freeze`.
* **Automatic Replication:** Seamless Server-to-Client state synchronization.
* **Middleware Support:** Easily extend functionality (Logging, DataStore saving, Analytics).
* **Time Travel:** Built-in Undo/Redo history system.
* **Performance:** Supports Batching and Partial Subscriptions (Selectors) for UI optimization.
* **Security:** Client-side is Read-Only by default; changes must be requested via RemoteEvents.

## Installation

### Wally (Recommended)
Add `StateStore` to your `wally.toml` file:

```toml
[dependencies]
StateStore = "glitchaether/state-store@0.0.1"
```

Then run:

```Bash
wally install
```

### Roblox

Coming soon

## Manual
Download the latest .rbxm release from the Releases page and drop it into ReplicatedStorage.

### Quick Start
Here is a simple example of how to define a store and listen for changes.

1. Define a Reducer (Server)

```Lua
local StateStore = require(game.ReplicatedStorage.Packages.StateStore)

-- The logic that decides how state changes
local function goldReducer(state, action)
    state = state or { gold = 0 }

    if action.type == "ADD_GOLD" then
        return { gold = state.gold + action.amount }
    end

    return state
end

-- Create the store
local MyStore = StateStore.new("PlayerStats", goldReducer)

-- Dispatch an action
MyStore:Dispatch({ type = "ADD_GOLD", amount = 100 })
```

2. Listen for Changes (Client)

```Lua
local StateStore = require(game.ReplicatedStorage.Packages.StateStore)

-- Get the mirror of the store created on the Server
local MyStore = StateStore.Get("PlayerStats")

-- Update UI only when gold changes
MyStore:Observe(function(state)
    return state.gold
end, function(newGold)
    print("My gold is now:", newGold)
end)
```

## Documentation
Full API reference, tutorials, and best practices are available at the documentation site:

https://glitchaether.github.io/modules/StateStore  (coming soon)

## License
StateStore is available under the MIT license. See LICENSE for details.