--[[
	Creates signals via a modulized version of RbxUtility (It was deprecated so This will be released for people who would like to keep using it.
	
	This creates RBXScriptSignals.
	
	API:
		table Signal:connect(Function f) --Will run f when the event fires.
		void Signal:wait() --Will wait until the event fires
		void Signal:disconnectAll() --Will disconnect ALL connections created on this signal
		void Signal:fire(Tuple args) --Cause the event to fire with your own arguments
		
		
		Connect, Wait, DisconnectAll, and Fire are also acceptable for calling (An uppercase letter rather than a lowercase one)
		
		
	Standard creation:
	
		local SignalModule = require(this module)
		local Signal = SignalModule:CreateNewSignal()
		
		function OnEvent()
			print("Event fired!")
		end
		
		Signal:Connect(OnEvent) --Unlike objects, this does not do "object.SomeEvent:Connect()" - Instead, the Signal variable is the event itself.
		
		Signal:Fire() --Fire it.
--]]

local Signal = {}

function Signal:CreateNewSignal()
	local This = {}

	local mBindableEvent = Instance.new('BindableEvent')
	local mAllCns = {} --All connection objects returned by mBindableEvent::connect

	function This:connect(Func)
		if typeof(Func) ~= "function" then
			error("Argument #1 of Connect must be a function, got a "..typeof(Func), 2)
		end
		local Con = mBindableEvent.Event:Connect(Func)
		mAllCns[Con] = true
		local ScrSig = {}
		function ScrSig:disconnect()
			Con:Disconnect()
			mAllCns[Con] = nil
		end
		
		ScrSig.Disconnect = ScrSig.disconnect
		
		return ScrSig
	end
	
	function This:disconnectAll()
		for Connection, _ in pairs(mAllCns) do
			Connection:Disconnect()
			mAllCns[Connection] = nil
		end
	end
	
	function This:wait()
		return mBindableEvent.Event:Wait()
	end
	
	function This:fire(...)
		mBindableEvent:Fire(...)
	end
	
	This.Connect = This.connect
	This.DisconnectAll = This.disconnectAll
	This.Wait = This.wait
	This.Fire = This.fire

	return This
end

return Signal
