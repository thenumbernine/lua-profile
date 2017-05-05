-- not sure what I want this to do ...

local funcs = {}
local cbname = '_profilerCallback'
local donename = '_profilerDone'
local lastTime = os.clock()

_G[donename] = function()
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

_G[cbname] = function(name, uid)
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

local uid = 0
local firstReq

local ast = require 'parser.ast'

require'parser.require'.callbacks:insert(function(tree)
	-- right here we should insert our profiler
	-- preferrably with its own id baked into it, so no id computation based on line #s is necessary
	local function addcbs(x)
		for k,v in pairs(x) do
			if type(v) == 'table' then
				if v.type == 'function' then
					uid = uid + 1
					table.insert(v, 1, ast._call(
						ast._var(cbname),
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
	if not firstReq then
		firstReq = true
		table.insert(tree, ast._call(ast._var(donename)))
	end
end)
