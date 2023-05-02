-- not sure what I want this to do ...
local template = require 'template'
local parser = require 'parser'
local ast = require 'parser.ast'

local funcs = {}

local lastTime = os.clock()

local function profileSummary()
	if not funcs then return end

	local s = {}
	for uid,f in pairs(funcs) do
		table.insert(s, f)
	end
	table.sort(s, function(a,b) return a.total < b.total end)

	for _,f in ipairs(s) do
		print(f.name..' '..f.uid)
		print('\tmin',f.min..'s')
		print('\tmax',f.max..'s')
		print('\tavg',f.avg..'s')
		print('\tstddev',math.sqrt(f.sqavg - f.avg*f.avg)..'s')
		print('\ttotal',f.total..'s')
		print('\tcount',f.count)
	end

	funcs = nil
end
-- what to call it in the local of each file
local profileSummaryName = '__profileSummary__'

local function profileCallback(name, uid)
	local thisTime = os.clock()
	local f = funcs[uid]
	if not f then
		f = {
			uid = uid,
			name = name,
			min = math.huge,
			max = -math.huge,
			avg = 0,
			sqavg = 0,
			total = 0,
			count = 0,
		}
		funcs[uid] = f
	end
	if lastTime then
		local dt = thisTime - lastTime
		if dt < f.min then f.min = dt end
		if dt > f.max then f.max = dt end
		f.count = f.count + 1
		f.avg = f.avg + (dt - f.avg) / f.count
		f.sqavg = f.sqavg + (dt*dt - f.sqavg) / f.count
		f.total = f.total + dt
	end
	lastTime = os.clock()
end
local profileCallbackName = '__profileCallback__'

local profileAPI = {
	profileSummary = profileSummary,
	profileCallback = profileCallback,
}
local profileAPIName = '__profilerAPI__'

local headerExprs = parser.parse(template([[
local <?=profileAPIName?> = require 'profile'
local <?=profileSummaryName?> = <?=profileAPIName?>.profileSummary
local <?=profileCallbackName?> = <?=profileAPIName?>.profileCallback
]], {
	profileAPIName = profileAPIName,
	profileSummaryName = profileSummaryName,
	profileCallbackName = profileCallbackName,
}))

-- uniquely identify each function
local uid = 0

-- used to flag the first required file and insert a printout of the summary afterwards
local firstReq

require'parser.require'.callbacks:insert(function(tree)
	-- right here we should insert our profiler
	-- preferrably with its own id baked into it, so no id computation based on line #s is necessary
	local function addcbs(x)
		for k,v in pairs(x) do
			if type(v) == 'table'
			and k ~= 'parent'	-- TODO need a list of child keys
			then
				if v.type == 'function' then
					uid = uid + 1
					table.insert(v, 1, ast._call(
						ast._var(profileCallbackName),
						ast._string(tostring(v.name or '<anon>')),
						ast._number(uid)
					))
					-- insert profile call here
				end
				addcbs(v)
			end
		end
	end
	addcbs(tree)

	for i=#headerExprs,1,-1 do
		table.insert(tree, 1, headerExprs[i])
	end

	-- [[ option #1: insert the summary at the end of the first require()
	-- only works with the convention of calling lua -lprofile -lscript-to-profile
	-- the downside of this is it ends with a lua console (unless you add -e "" at the end)
	if not firstReq then
		firstReq = true
		table.insert(tree, ast._call(ast._var(profileSummaryName)))
	end
	--]]
end)

--[[ option #2: insert the summary as a gc of this.
-- it so long as you return it and it embeds in the package.loaded,
-- it won't get called until the shutdown
-- downside is that if you don't add the -e , and remain in interpreter mode, it won't show the summary
-- and calling os.exit() from interpreter bypasses all lua table __gc's
-- i.e. the -e "" is essential
return setmetatable({}, {__gc=function()
	profileSummary()
end})
--]]

return {
	profileSummary = profileSummary,
	profileCallback = profileCallback,
}
