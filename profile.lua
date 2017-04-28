-- not sure what I want this to do ...
local Parser = require 'parser'
--local showcode = require 'template.showcode'
local totalLines = 0
local oldrequire = require
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
print('parsing filename',fn)
--print(showcode(str))
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
				local function rmap(x)
					for k,v in pairs(x) do
						if type(v) == 'table' then
							if v.type == 'block' then
								-- insert profile call here
							end
							rmap(v)
						end
					end
				end
				rmap(tree)

				str = tostring(tree)
--print('parsed code:\n'..showcode(str))
print('total lines parsed:',totalLines)				
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
