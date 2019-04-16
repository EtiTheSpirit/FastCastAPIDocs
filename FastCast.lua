--[[
	FastCast Ver. 7.0.0
	Written by Xan_TheDragon
	
		The latest patch notes can be located here: https://github.com/XanTheDragon/FastCastAPIDocs/wiki/Changelist
		
		*** If anything is broken, please don't hesitate to message me! ***
		
		YOU CAN FIND IMPORTANT USAGE INFORMATION HERE: https://github.com/XanTheDragon/FastCastAPIDocs/wiki
		YOU CAN FIND IMPORTANT USAGE INFORMATION HERE: https://github.com/XanTheDragon/FastCastAPIDocs/wiki
		YOU CAN FIND IMPORTANT USAGE INFORMATION HERE: https://github.com/XanTheDragon/FastCastAPIDocs/wiki
		
		YOU SHOULD ONLY CREATE ONE CASTER PER GUN.
		YOU SHOULD >>>NEVER<<< CREATE A NEW CASTER EVERY TIME THE GUN NEEDS TO BE FIRED.
		
		A caster (created with FastCast.new()) represents a "gun".
		When you consider a gun, you think of stats like accuracy, bullet speed, etc. This is the info a caster stores. 
	
	--
	
	This is a library used to create hitscan-based guns that simulate projectile physics.
	
	This means:
		- You don't have to worry about bullet lag / jittering
		- You don't have to worry about keeping bullets at a low speed due to physics being finnicky between clients
		- You don't have to worry about misfires in bullet's Touched event (e.g. where it may going so fast that it doesn't register)
		
	Hitscan-based guns are commonly seen in the form of laser beams, among other things. Hitscan simply raycasts out to a target
	and says whether it hit or not.
	
	Unfortunately, while reliable in terms of saying if something got hit or not, this method alone cannot be used if you wish
	to implement bullet travel time into a weapon. As a result of that, I made this library - an excellent remedy to this dilemma.
	
	FastCast is intended to be require()'d once in a script, as you can create as many casters as you need with FastCast.new()
	This is generally handy since you can store settings and information in these casters, and even send them out to other scripts via events
	for use.
	
	Remember -- A "Caster" represents an entire gun (or whatever is launching your projectiles), *NOT* the individual bullets.
	Make the caster once, then use the caster to fire your bullets. Do not make a caster for each bullet.
--]]

local FastCast = {}

--https://roblox.com/library/2530470096/rbxscriptsignal
--If you are only going to be requiring this from the server you can require by its asset ID.
local Signal = require(script:WaitForChild("Signal")) 
local RunService = game:GetService("RunService")

--[[
	Creates a new caster.
	Please see the long comment at the top of the script for what methods you can use.
--]]
function FastCast.new()
	--Set up main object.
	local Caster = {}
	local CMeta = {}
	setmetatable(Caster, CMeta)
	
	--Set up local properties.
	local IgnoreDescendantsInstance = nil
	local Gravity = 0
	local ExtraForce = Vector3.new()
	
	--Set up connections
	local RayHit = Signal:CreateNewSignal()
	local LengthChanged = Signal:CreateNewSignal()
	
	--UsingPhysics is returned when you reference Caster.HasPhysics (The value returned by this function is given)
	local function UsingPhysics()
		return (Gravity ~= 0) or (ExtraForce.Magnitude ~= 0)
	end
	
	--This function casts a ray from origin in the specified direction.
	local function Cast(Origin, Direction)
		local CastRay = Ray.new(Origin, Direction)
		return workspace:FindPartOnRay(CastRay, IgnoreDescendantsInstance)
	end
	
	--This function casts a ray with a whitelist.
	local function CastWhitelist(Origin, Direction, Whitelist)
		if not Whitelist or typeof(Whitelist) ~= "table" then
			--Faulty array. Throw an error.
			error("Call in CastWhitelist failed! Whitelist table is either nil, or is not actually a table.", 0)
		end
		local CastRay = Ray.new(Origin, Direction)
		return workspace:FindPartOnRayWithWhitelist(CastRay, Whitelist)
	end
	
	--This function casts a ray with a blacklist.
	local function CastBlacklist(Origin, Direction, Blacklist)
		if not Blacklist or typeof(Blacklist) ~= "table" then
			--Faulty array. Throw an error.
			error("Call in CastBlacklist failed! Blacklist table is either nil, or is not actually a table.", 0)
		end
		--If the array list is empty, 
		local CastRay = Ray.new(Origin, Direction)
		return workspace:FindPartOnRayWithIgnoreList(CastRay, Blacklist)
	end
	
	--Thanks to zoebasil for supplying the velocity and position functions below. (I've modified these functions)
	--I was having a huge issue trying to get it to work and I had overcomplicated a bunch of stuff.
	--GetPositionAtTime is used in physically simulated rays (Where Caster.HasPhysics == true).
	--This returns the location that the bullet will be at when you specify the amount of time the bullet has existed, the original location of the bullet, and the velocity it was launched with.
	local function GetPositionAtTime(Time, Origin, InitialVelocity, Acceleration)
		local Gravity = Gravity * -1
		local Force = Vector3.new((Acceleration.X * Time^2) / 2,(Acceleration.Y * Time^2) / 2, (Acceleration.Z * Time^2) / 2)
		local GravForce = Vector3.new(0, (Gravity * (Time^2))/2, 0)
		return Origin + (InitialVelocity * Time) + Force + GravForce
	end
	
	--Fire with physics.
	local function MainCastFire(Origin, Direction, Velocity, Function, CosmeticBulletObject, List, BulletAcceleration)
		--UPDATE V6: Velocity can now be a Vector3. If it is still a numeric value, we just need to convert it into a Vector3.
		--TO DO: Deprecate direction because of this? EDIT: No, don't, since we can use that for our bullet orientation.
		if type(Velocity) == "number" then
			Velocity = Direction.Unit * Velocity
		end
		
		local Distance = Direction.Magnitude
		local NormalizedDir = Direction / Distance
		local UpgradedDir = (NormalizedDir + Velocity).Unit
		local InitialVelocity = (UpgradedDir * Velocity.Magnitude)
		
		local TotalDelta = 0
		local DistanceTravelled = 0
		local LastPoint = Origin
		while DistanceTravelled <= Distance do
			local Delta = RunService.Heartbeat:Wait()
			TotalDelta = TotalDelta + Delta
			local At = GetPositionAtTime(TotalDelta, Origin, InitialVelocity, BulletAcceleration or ExtraForce)
			
			local ATDifference = (At - LastPoint)
			local ATDirection = ATDifference.Unit
			local ATDistance = ATDifference.Magnitude
			local RayDir = ATDirection * Velocity.Magnitude * Delta
			local Hit, Point, Normal, Material = Function(LastPoint, RayDir, List)
			--Fire this before the return
			--Get the extra distance. If we didn't hit anything, ExtraDistance will be the same as RayDir's Magnitude.
			--If we DID hit something, it'll be the length from the current start to the hit location.
			--This means that any tracer should be set based on a rotated CFrame pushed outward by the distance.
			
			local LastToCurrent_Distance = (LastPoint - At).Magnitude
--			local EndToCurrent_Distance = (At - Point).Magnitude
--			local Change = (LastToCurrent_Distance - EndToCurrent_Distance)
			
			LengthChanged:Fire(Origin, LastPoint, RayDir.Unit, LastToCurrent_Distance, CosmeticBulletObject)
			LastPoint = At
			if Hit then
				--V5: WAIT! Test if the cosmetic bullet was hit!
				if Hit ~= CosmeticBulletObject then
					--Hit something, stop the function and fire the hit event.
					RayHit:Fire(Hit, Point, Normal, Material, CosmeticBulletObject)
					return
				end
				--If we make it here, then the bullet isn't nil, and it was the hit.(The above code exits the function)
				--This will ignore the bullet. For this function, no changes need to be made.
			end
			DistanceTravelled = DistanceTravelled + LastToCurrent_Distance
		end
		--If we make it here, then we have exceeded the maximum distance.
		--As part of Ver. 4, the hit function will fire here.
		--V5: Changed below to return all nil values aside from the point
		RayHit:Fire(nil, LastPoint, nil, nil, CosmeticBulletObject)
	end
	
	--Fire without physics
	local function MainCastFireNoPhys(Origin, Direction, Velocity, Function, CosmeticBulletObject, List)
		if type(Velocity) == "number" then
			Velocity = Direction.Unit * Velocity
		end
		
		local Distance = Direction.Magnitude
		local NormalizedDir = Direction / Distance
		
		local LastPoint = Origin
		local DistanceTravelled = 0
		while DistanceTravelled <= Distance do
			local Delta = RunService.Heartbeat:Wait()
			local UpgradedDir = (NormalizedDir + Velocity).Unit
			local Start = Origin + (UpgradedDir.Unit * DistanceTravelled)
			local RayDir = UpgradedDir * Velocity.Magnitude * Delta
			local Hit, Point, Normal, Material = Function(Start, RayDir, List)
			
			local ExtraDistance = (Start - Point).Magnitude
			local ModifiedDistance = DistanceTravelled + ExtraDistance
			
			--Note to self: ExtraDistance will be identical to RayDir.Magnitude unless something is hit.	
			LengthChanged:Fire(Origin, LastPoint, RayDir.Unit, ExtraDistance, CosmeticBulletObject)
			
			
			LastPoint = Point
			if Hit then
				--V5: WAIT! Test if the cosmetic bullet was hit!
				if Hit ~= CosmeticBulletObject then
					--Hit something, stop the function and fire the hit event.
					RayHit:Fire(Hit, Point, Normal, Material, CosmeticBulletObject)
					return
				end
				--If we make it here, then the bullet isn't nil, and it was the cosmetic bullet that got hit. (The above code exits the function)
				--In this case, we will kindly ignore the bullet.
				--We will also set ExtraDistance to RayDir.Magnitude (See above - These two values are identical if nothing is hit, so we need to force that behavior)
				ExtraDistance = RayDir.Magnitude
			end
			DistanceTravelled = DistanceTravelled + ExtraDistance
		end
		--V5: Changed below to return all nil values aside from the point
		RayHit:Fire(nil, LastPoint, nil, nil, CosmeticBulletObject)
	end
	
	--Fire a ray from origin -> direction at the specified velocity.
	function Caster:Fire(Origin, Direction, Velocity, CosmeticBulletObject, BulletAcceleration)
		--Note to scripters: 'self' is a variable lua creates when a method like ^ is run. It's an alias to the table that the function is part of (in this case, Caster)
		assert(Caster == self, "Expected ':' not '.' calling member function Fire")
		
		spawn(function ()
			if UsingPhysics() or BulletAcceleration then
				MainCastFire(Origin, Direction, Velocity, Cast, CosmeticBulletObject, nil, BulletAcceleration)
			else
				MainCastFireNoPhys(Origin, Direction, Velocity, Cast, CosmeticBulletObject)
			end
		end)
	end
	
	--Identical to above, but with a whitelist.
	function Caster:FireWithWhitelist(Origin, Direction, Velocity, Whitelist, CosmeticBulletObject, BulletAcceleration)
		--Note to scripters: 'self' is a variable lua creates when a method like ^ is run. It's an alias to the table that the function is part of (in this case, Caster)
		assert(Caster == self, "Expected ':' not '.' calling member function FireWithWhitelist")
		spawn(function ()
			if UsingPhysics() or BulletAcceleration then
				MainCastFire(Origin, Direction, Velocity, CastWhitelist, CosmeticBulletObject, Whitelist, BulletAcceleration)
			else
				MainCastFireNoPhys(Origin, Direction, Velocity, CastWhitelist, CosmeticBulletObject, Whitelist)
			end
		end)
	end
	
	--Identical to above, but with a blacklist.
	function Caster:FireWithBlacklist(Origin, Direction, Velocity, Blacklist, CosmeticBulletObject, BulletAcceleration)
		--Note to unaware scripters: 'self' is a variable lua creates when a method like ^ is run. It's an alias to the table that the function is part of (in this case, Caster)
		assert(Caster == self, "Expected ':' not '.' calling member function FireWithBlacklist")
		spawn(function ()
			if UsingPhysics() or BulletAcceleration then
				MainCastFire(Origin, Direction, Velocity, CastBlacklist, CosmeticBulletObject, Blacklist, BulletAcceleration)
			else
				MainCastFireNoPhys(Origin, Direction, Velocity, CastBlacklist, CosmeticBulletObject, Blacklist)
			end
		end)
	end
	
	
	--Indexing stuff here.
	--For those scripters new to Metatables, they allow you to fake information in tables by controlling how it works.
	--This function will be run when you try to index anything of the fastcaster.
	--If I were to do Caster["CoolIndex"], this function would fire, table being Caster, and Index being "CoolIndex".
	--This means that I can return my own value, even if "CoolIndex" isn't valid.
	--Neat, huh?
	CMeta.__index = function (Table, Index)
		if Table == Caster then
			if Index == "IgnoreDescendantsInstance" then
				return IgnoreDescendantsInstance
			elseif Index == "RayHit" then
				return RayHit
			elseif Index == "LengthChanged" then
				return LengthChanged
			elseif Index == "Gravity" then
				return Gravity
			elseif Index == "ExtraForce" then
				return ExtraForce
			elseif Index == "HasPhysics" then
				return UsingPhysics()
			end
		end
	end
	
	local IgnoreMode = false -- This is used so I can do some tricks below 
	--Same thing as above, just that this fires writing to the table (e.g. Caster["CoolIndex"] = "CoolValue")
	CMeta.__newindex = function (Table, Index, Value)
		if IgnoreMode then return end
		if Table == Caster then
			if Index == "IgnoreDescendantsInstance" then
				assert(Value == nil or typeof(Value) == "Instance", "Bad argument \"" .. Index .. "\" (Instance expected, got " .. typeof(Value) .. ")")
				IgnoreDescendantsInstance = Value
			elseif Index == "Gravity" then
				assert(typeof(Value) == "number", "Bad argument \"" .. Index .. "\" (number expected, got " .. typeof(Value) .. ")")
				Gravity = Value			
			elseif Index == "ExtraForce" then
				assert(typeof(Value) == "Vector3", "Bad argument \"" .. Index .. "\" (Vector3 expected, got " .. typeof(Value) .. ")")
				ExtraForce = Value
			elseif Index == "RayHit" or Index == "LengthChanged" or Index == "HasPhysics" then
				error("Can't set value", 0)
			end
		end
	end

	--TRICK: I'm going to make dummy values for the properties and events.
	--Roblox will show these in intellesence (the thing that suggests what to type in as you go)
	IgnoreMode = true
	Caster.RayHit = RayHit
	Caster.LengthChanged = LengthChanged
	Caster.IgnoreDescendantsInstance = IgnoreDescendantsInstance
	Caster.Gravity = Gravity
	Caster.ExtraForce = ExtraForce
	Caster.HasPhysics = UsingPhysics()
	IgnoreMode = false
	--Better yet, while these values are just in the open, they will still be managed by the metatables.
	
	CMeta.__metatable = "FastCaster"
	
	return Caster
end

return FastCast
