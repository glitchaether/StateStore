--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_EVENT_NAME = "StateStore_Sync"

export type Action = { type: string, payload: any?, [any]: any }
export type Listener<S> = (newState: S, oldState: S) -> ()
export type Reducer<S> = (state: S, action: Action) -> S
export type Selector<S, V> = (state: S) -> V

export type Store<S> = {
	GetState: (self: Store<S>) -> S,
	Dispatch: (self: Store<S>, action: Action) -> any,
	Subscribe: (self: Store<S>, listener: Listener<S>) -> () -> (),
	Observe: <V>(self: Store<S>, selector: Selector<S, V>, listener: (newValue: V, oldValue: V) -> ()) -> () -> (),

	Batch: (self: Store<S>, callback: () -> ()) -> (),
	Undo: (self: Store<S>) -> boolean,
	Redo: (self: Store<S>) -> boolean,
	Hydrate: (self: Store<S>, state: S) -> (),
	Dehydrate: (self: Store<S>) -> S,

	StartRecording: (self: Store<S>) -> (),
	StopRecording: (self: Store<S>) -> (),
	GetReplayData: (self: Store<S>) -> { { time: number, action: Action } },

	Destroy: (self: Store<S>) -> ()
}

local StateStore = {}

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local copy = {}
	for k, v in pairs(t) do
		if type(v) == "table" then
			copy[k] = deepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy
end

local StoreClass = {}
StoreClass.__index = StoreClass

function StoreClass.new(reducer, initialState)
	local self = setmetatable({}, StoreClass)

	self._reducer = reducer
	self._state = initialState
	self._listeners = {} 
	self._isDispatching = false

	self._isBatching = false
	self._batchChanged = false
	self._batchOldState = nil

	self._history = {}
	self._future = {}
	self._maxHistory = 50

	self._isRecording = false
	self._recordingData = {}
	self._recordStartTime = 0

	if type(self._state) == "table" then
		table.freeze(self._state)
	end

	self:_CoreDispatch({ type = "@@INIT" })

	return self
end

function StoreClass:GetState()
	return self._state
end

function StoreClass:_Notify(oldState)
	if self._isBatching then
		self._batchChanged = true
		return
	end

	local newState = self._state

	for _, sub in ipairs(self._listeners) do
		if sub.type == "standard" then
			task.spawn(sub.callback, newState, oldState)

		elseif sub.type == "observer" then
			local successNew, newVal = pcall(sub.selector, newState)
			local successOld, oldVal = pcall(sub.selector, oldState)

			if successNew and successOld and newVal ~= oldVal then
				task.spawn(sub.callback, newVal, oldVal)
			end
		end
	end
end

function StoreClass:_CoreDispatch(action)
	if self._isDispatching then error("Reducers may not dispatch actions.") end

	local oldState = self._state

	if self._isRecording then
		table.insert(self._recordingData, {
			time = os.clock() - self._recordStartTime,
			action = action
		})
	end

	self._isDispatching = true
	local success, newStateOrError = pcall(function() return self._reducer(oldState, action) end)
	self._isDispatching = false

	if success then
		if newStateOrError == oldState then return false end

		if action.type ~= "@@UNDO" and action.type ~= "@@REDO" and action.type ~= "@@HYDRATE" then
			table.insert(self._history, oldState)
			if #self._history > self._maxHistory then table.remove(self._history, 1) end
			table.clear(self._future)
		end

		self._state = newStateOrError
		if type(self._state) == "table" then table.freeze(self._state) end

		self:_Notify(oldState)

		return true
	else
		warn("[StateStore] Reducer Error:", newStateOrError)
		return false
	end
end

function StoreClass:Batch(callback)
	if self._isBatching then
		callback()
		return
	end

	self._isBatching = true
	self._batchChanged = false
	self._batchOldState = self._state

	local success, err = pcall(callback)

	self._isBatching = false

	if success then
		if self._batchChanged then
			self:_Notify(self._batchOldState)
		end
	else
		warn("[StateStore] Batch Error:", err)
	end

	self._batchOldState = nil
end

function StoreClass:Observe(selector, callback)
	local sub = {
		type = "observer",
		selector = selector,
		callback = callback
	}
	table.insert(self._listeners, sub)

	return function()
		local idx = table.find(self._listeners, sub)
		if idx then table.remove(self._listeners, idx) end
	end
end

function StoreClass:Subscribe(callback)
	local sub = { type = "standard", callback = callback }
	table.insert(self._listeners, sub)
	return function()
		local idx = table.find(self._listeners, sub)
		if idx then table.remove(self._listeners, idx) end
	end
end

function StoreClass:Undo()
	if #self._history == 0 then return false end

	local previousState = table.remove(self._history)
	table.insert(self._future, self._state)

	self._state = previousState
	self:_Notify(self._future[#self._future])

	return true
end

function StoreClass:Redo()
	if #self._future == 0 then return false end

	local nextState = table.remove(self._future)
	table.insert(self._history, self._state)

	self._state = nextState
	self:_Notify(self._history[#self._history])

	return true
end

function StoreClass:Dehydrate()
	return deepCopy(self._state)
end

function StoreClass:Hydrate(data)
	self:_CoreDispatch({ type = "@@HYDRATE" })

	self._state = data
	if type(self._state) == "table" then table.freeze(self._state) end
	self:_Notify(self._history[#self._history] or {})
end

function StoreClass:StartRecording()
	self._isRecording = true
	self._recordingData = {}
	self._recordStartTime = os.clock()
end

function StoreClass:StopRecording()
	self._isRecording = false
end

function StoreClass:GetReplayData()
	return deepCopy(self._recordingData)
end

if RunService:IsServer() then
	local remote = ReplicatedStorage:FindFirstChild(REMOTE_EVENT_NAME)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_EVENT_NAME
		remote.Parent = ReplicatedStorage
	end

	local registeredStores = {}

	function StateStore.new(name, reducer, initialState, middlewares)
		if registeredStores[name] then error("Store exists: "..name) end
		local store = StoreClass.new(reducer, initialState)

		local function finalDispatch(action)
			local changed = store:_CoreDispatch(action)
			if changed then
				remote:FireAllClients(name, store._state)
			end
			return action
		end

		if middlewares and #middlewares > 0 then
			local api = { GetState = function() return store:GetState() end, Dispatch = function(a) return store:Dispatch(a) end }
			local chain = {}
			for _, m in ipairs(middlewares) do table.insert(chain, m(api)) end
			local dispatch = finalDispatch
			for i = #chain, 1, -1 do dispatch = chain[i](dispatch) end
			store.Dispatch = function(_, a) return dispatch(a) end
		else
			store.Dispatch = function(_, a) return finalDispatch(a) end
		end

		game:GetService("Players").PlayerAdded:Connect(function(p)
			remote:FireClient(p, name, store:GetState())
		end)

		registeredStores[name] = store
		return store
	end

elseif RunService:IsClient() then
	local remote = ReplicatedStorage:WaitForChild(REMOTE_EVENT_NAME)
	local clientStores = {}

	function StateStore.Get(name)
		if clientStores[name] then return clientStores[name] end

		local store = StoreClass.new(function(s, a) 
			return a.type == "__SYNC" and a.payload or s 
		end, {})

		function store:Dispatch(action)
			if action.type == "__SYNC" then self:_CoreDispatch(action)
			else warn("Client cannot dispatch directly.") end
		end

		clientStores[name] = store
		return store
	end

	remote.OnClientEvent:Connect(function(name, newState)
		if clientStores[name] then
			clientStores[name]:Dispatch({ type = "__SYNC", payload = newState })
		end
	end)
end

return StateStore