-- not sure what I want this to do ...
local template = require 'template'
local LuaParser = require 'parser.lua.parser'

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
		print(f.name
			..' id#'..f.uid
			..' '..tostring(f.source)
			..':'..tostring(f.line)
			..':'..tostring(f.col))
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

local function profileCallback(name, uid, source, line, col)
	-- profile callback hit after we've reported the summary ...
	if not funcs then return end

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
			source = source,
			line = line,
			col = col,
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

local headerExprs = LuaParser.parse(template([[
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

local ast = LuaParser.ast
require'parser.load_xform':insert(function(tree, source)
	-- right here we should insert our profiler
	-- preferrably with its own id baked into it, so no id computation based on line #s is necessary
	local function addcbs(x)
		for k,v in pairs(x) do
			if type(v) == 'table'
			and k ~= 'parent'	-- TODO need a list of child keys
			and k ~= 'parser'
			then
				if v.type == 'function' then
					uid = uid + 1
					local loc = v.span.from
--DEBUG:print('inserting profile at', v.span.from.source, v.span.from.line, v.span.from.col)
					-- insert profile call here
					table.insert(v, 1, ast._call(
						ast._var(profileCallbackName),
						ast._string(tostring(v.name or '<anon>')),
						ast._number(uid),
						ast._string(source), --loc.source),
						ast._number(loc.line),
						ast._number(loc.col)
					))
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
		local laststmt = tree[#tree]
		if ast._return:isa(laststmt) then
			-- if there's a return at the end ...
			-- then we need to execute this after evaluating the return expression but before returning the value ...
			tree[#tree] = ast._return(
				ast._call(
					ast._par(
						ast._function(
							nil,
							{},
							ast._local{
								ast._assign(
									{ast._var'tmp'},
									laststmt.exprs
								)
							},
							ast._call(ast._var(profileSummaryName)),
							ast._return(ast._var'tmp')
						)
					)
				)
			)
		else
			table.insert(tree, ast._call(ast._var(profileSummaryName)))
		end
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
