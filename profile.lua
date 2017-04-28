-- not sure what I want this to do ...
local Parser = require 'parser'
local ast = require 'parser.ast'

local oldrequire = require

local funcs = {}
local cbname = '_profilerCallback'
local donename = '_profilerDone'
local lastTime = os.clock()

_G[donename] = function()
	if not funcs then return end
	for uid,f in pairs(funcs) do
		local f = assert(funcs[uid])
		print(f.name..' '..uid)
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
	end
	lastTime = os.clock()
end

local uid = 0
local totalLines = 0
local firstReq
function require(m, ...)
	local result = package.loaded[m]
	if result ~= nil then return result end
	local result = package.preload[m]
	local err = {"module '"..m.."' not found:"}
	if result ~= nil then
		result = result()
		package.loaded[m] = result
		return result
	end
	table.insert(err, "\tno field package.preload['"..m.."']")
	for path in package.path:gmatch'[^;]+' do
		local fn = path:gsub('%?', (m:gsub('%.', '/')))
		local f = io.open(fn, 'rb')
		if f then
			local str = f:read'*a'
			if f then f:close() end
			if str then
				-- here i'm going to insert a profiling call into each function
--print('parsing filename',fn)
				totalLines = totalLines + #str:gsub('\n+','\n'):gsub('[^\n]','') + 1
				local parser
				local result, tree = xpcall(function()
					parser = Parser()
					parser:setData(str)
					return parser.tree
				end, function(err)
					return err..'\n'..debug.traceback()
				end)
				if not result then
					error('\n\t'..fn..' at '..parser.t:getpos()..'\n'..tree)
				end
				
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

				str = tostring(tree)
print('parsed '..fn..' total lines:',totalLines)
				result = assert(load(str))()
				package.loaded[m] = result
				return result
			end
		end
		table.insert(err, "\tno field '"..fn.."'")
	end
	for path in package.cpath:gmatch'[^;]+' do
		local fn = path:gsub('%?', (m:gsub('%.', '/')))
		local f = io.open(fn, 'rb')
		if f then
			f:close()
			local result = assert(package.loadlib(fn, m))()
			package.loaded[m] = result
			return result
		end
		table.insert(err, "\tno field '"..fn.."'")
	end
	error(table.concat(err, '\n'))
end
