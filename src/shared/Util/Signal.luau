--!strict
-- Minimal signal for server services and client controllers. Each handler runs in its own
-- thread (task.spawn), so a handler that errors or yields never blocks the others.

local Signal = {}

export type Connection = { Connected: boolean, Disconnect: (self: Connection) -> () }

export type Signal = {
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Once: (self: Signal, fn: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
}

function Signal.new(): Signal
	local connections: { any } = {}
	local signal = {} :: any

	local function connect(fn: (...any) -> (), once: boolean): Connection
		local connection = { Connected = true } :: any
		local function disconnect()
			if connection.Connected then
				connection.Connected = false
				local index = table.find(connections, connection)
				if index then
					table.remove(connections, index)
				end
			end
		end
		connection.Disconnect = disconnect
		connection.fn = if once
			then function(...)
				disconnect()
				fn(...)
			end
			else fn
		table.insert(connections, connection)
		return connection
	end

	function signal.Connect(_: any, fn: (...any) -> ()): Connection
		return connect(fn, false)
	end

	function signal.Once(_: any, fn: (...any) -> ()): Connection
		return connect(fn, true)
	end

	function signal.Fire(_: any, ...: any)
		for _, connection in table.clone(connections) do
			if connection.Connected then
				task.spawn(connection.fn, ...)
			end
		end
	end

	function signal.Wait(_: any): ...any
		local thread = coroutine.running()
		connect(function(...)
			task.spawn(thread, ...)
		end, true)
		return coroutine.yield()
	end

	return signal :: Signal
end

return Signal
