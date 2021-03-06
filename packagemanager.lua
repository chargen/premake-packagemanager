---
-- Package management module
-- Copyright (c) 2014-2017 Blizzard Entertainment
---

local p = premake

p.modules.packagemanager = {}
p.modules.packagemanager._VERSION = p._VERSION

local m = p.modules.packagemanager

--[ Global package manager namespace ] ----------------------------------------

p.packagemanager = {
	cache_location    = nil,
	folders           = {},
	aliases           = {},
	servers           = {
		'http://***REMOVED***',
		'http://***REMOVED***'
	},
	systems = {
		dofile("package_v2.lua"),
		dofile("package_v1.lua"),
	},
}

local pm = p.packagemanager

-- include the rest of the module ---------------------------------------------

include 'util.lua'
include 'context.lua'
include 'httpext.lua'
include 'variant.lua'
include 'package.lua'
include 'package_base.lua'
include 'package_project.lua'
include 'packageresolver.lua'
include 'deprecated.lua'

--[ local private variables ] -------------------------------------------------

local __loaded = {}
local __aliases = {}
local __loadedLockFile = nil

--[ private functions ]----------------------------------------------------

---
-- Get the alias information from the package server.
---
	local function __getAliasTable(name)
		-- if we don't want server queries, just return the local results.
		if _OPTIONS['no-http'] or (pm.servers == nil) then
			if pm.aliases[name] then
				local aliases = {}
				for _, alias in ipairs(pm.aliases[name]) do
					table.insert(aliases, alias:lower())
					print(alias)
				end
				return name:lower(), aliases
			end
			return name:lower(), {}
		end

		-- query servers for alias information.
		local link = '/aliases?name=' .. http.escapeUrlParam(name)
		local tbl = http.getJson(pm.servers, link)
		if tbl ~= nil then
			local aliases = {}
			for _, alias in ipairs(tbl.Aliases or {}) do
				table.insert(aliases, alias:lower())
			end
			return tbl.RealName:lower(), aliases
		end

		return name:lower(), {}
	end

	local function __getRealname(name)
		local realname, aliases = __getAliasTable(name)
		if name:lower() ~= realname:lower() then
			p.warn("Using the alias '%s' is deprecated, use the real name '%s'.", name, realname)
		end
		return realname
	end

---
-- Load lockfile.
---
	local function __loadLockFile()
		if __loadedLockFile ~= nil then
			return __loadedLockFile
		end

		local g = p.api.rootContainer()
		local fn = g.lockfile or path.join(_MAIN_SCRIPT_DIR, ".lockfile")

		local text = io.readfile(fn)
		if text == nil then
			__loadedLockFile = {}
		else
			local result, err = json.decode(text)
			if result == nil then
				p.error(err)
			end
			__loadedLockFile = result
		end

		return __loadedLockFile
	end


---
-- Find the first version that matches the pattern.
---
	local function __findVersion(name, pattern)
		local versions = {}

		-- if we don't want to do any http queries, exit.
		if _OPTIONS['no-http'] then
			return nil
		end

		-- ask server for a sorted list of available versions
		local link = '/api/v1/versions/' .. http.escapeUrlParam(name)
		local tbl = http.getJson(pm.servers, link)
		if tbl ~= nil then
			for _, entry in ipairs(tbl) do
				local v = entry.version
				if v:match(pattern) == v then
					table.insert(versions, v)
				end
			end
		end

		-- no matching results?
		if #versions <= 0 then
			return nil
		end

		-- first result is best available match.
		return versions[1]
	end

---
-- Find the first version that matches the pattern.
---

	local function __getGitVersion(name, version)
		-- if we don't want to do any http queries, exit.
		if _OPTIONS['no-http'] then
			return nil
		end

		-- ask for the type of package, which returns a pre-cached release.
		local link = '/api/v1/type/' .. http.escapeUrlParam(name) .. '/' .. http.escapeUrlParam(version)
		local tbl = http.getJson(pm.servers, link)

		if tbl ~= nil then
			return tbl.version
		end

		return nil
	end

---
-- Import a single package...
---
	local function __importPackage(name, version)
		-- create the --use-<name> option.
		local optionname = 'use-' .. name
		p.option.add({
			trigger     = optionname,
			value       = '<path>',
			default     = version,
			description = 'Path or Version for ' .. name .. ' package.',
			category    = 'Package Manager'
		})

		-- option overrides version from table.
		version = _OPTIONS[optionname] or version

		-- test if there is a '*' in the version number...
		if version:contains('*') then
			local lockfile = __loadLockFile()
			local pattern = path.wildcards(version)
			local id = name .. '/' .. version

			-- Find in LockFile
			local v = lockfile[id]

			-- If we didn't find it in the lockfile, find a matching version.
			if v == nil then
				v = __findVersion(name, pattern)
				if v == nil then
					p.error("No version matching the pattern '%s', was found for package '%s'.", version, name)
				else
					p.info("Found '%s' for '%s', pattern: '%s'.", v, name, version)
				end
			else
				p.info("Using '%s' for '%s', pattern: '%s'.", v, name, version)
			end

			-- Update version.
			version = v

			-- and store in global lockfile.
			local g = p.api.rootContainer()
			g.__lockfile = g.__lockfile or {}
			g.__lockfile[id] = v
		end

		-- deal with translating git| versions.
		if version:startswith("git|") then
			local lockfile = __loadLockFile()
			local id = name .. '/' .. version

			-- Find in LockFile
			local v = lockfile[id]

			-- If we didn't find it in the lockfile, we need to ask the server for a hash.
			if v == nil then
				v = __getGitVersion(name, version)
				if v == nil then
					p.error("No git hash was found for package '%s' using reference '%s'.", name, version:sub(5))
				else
					p.info("Found '%s' for '%s', reference: '%s'.", v, name, version:sub(5))
				end
			else
				p.info("Using '%s' for '%s', reference: '%s'.", v, name, version:sub(5))
			end

			-- Update version.
			version = 'git|' .. v

			-- and store in global lockfile.
			local g = p.api.rootContainer()
			g.__lockfile = g.__lockfile or {}
			g.__lockfile[id] = v
		end

		-- now initialize the package.
		for _, pkgsys in ipairs(pm.systems) do
			local pkg = pkgsys(name, version)
			if pkg ~= nil then
				return pkg
			end
		end

		p.error("No package '%s' version '%s' was found.", name, version)
	end


	local function __setPackageOptions(pkg, options)
		-- initialize options table with defaults.
		if pkg.options then
			for name, f in pairs(pkg.options) do
				f._proc = premake.field.accessor({_kind=f.kind}, "store")
				if f.default ~= nil then
					pkg.optionValues[name] = f._proc(nil, nil, f.default, nil)
				end
			end
		end

		-- set options set through import.
		if options ~= nil then
			if not pkg.options then
				p.error("Package '%s' has no options.", pkg.name)
			end

			for name, value in pairs(options) do
				local f = pkg.options[name]
				if f == nil then
					p.error("Package '%s' has no '%s' option.", pkg.name, name)
				end
				pkg.optionValues[name] = f._proc(nil, nil, value, nil)
			end
		end

		-- check if all required options have a value.
		if pkg.options then
			for name, f in pairs(pkg.options) do
				if f.required and pkg.optionValues[name] == nil then
					p.error("Option '%s' is required for package '%s'.", name, pkg.name)
				end
			end
		end
	end


--[ public functions ]----------------------------------------------------

---
-- Get the location of where the package manager should download packages.
---
	function pm.getCacheLocation()
		local folder = os.getenv('PACKAGE_CACHE_PATH')
		if folder then
			return folder
		else
			if pm.cache_location then
				return pm.cache_location
			end
			return path.join(_MAIN_SCRIPT_DIR, _OPTIONS.to or 'build', 'package_cache')
		end
	end


---
-- Import packages.
---
	function pm.import(tbl)
		if (not tbl) or (type(tbl) ~= "table") then
			local caller = filelineinfo(2)
			p.error("Invalid argument to import.\n   @%s\n", caller)
		end

		-- we always need to have a workspace.
		local scope = p.api.scope.current
		local wks   = p.api.scope.workspace
		if wks == nil then
			local caller = filelineinfo(2)
			p.error("No workspace is currently in scope.\n   @%s\n", caller)
		end

		-- override the 'group' function, packages shouldn't call it.
		local groupFunc = _G['group']
		_G['group'] = function(name)
			local caller = filelineinfo(2)
			p.warn("Using group '%s' inside package script.\n   @%s\n", name, caller)
		end

		-- import packages.
		local init_table = {}
		for name, version in pairs(tbl) do
			local realname, aliases = __getAliasTable(name)

			if name:lower() ~= realname:lower() then
				local caller = filelineinfo(2)
				p.warn("Using the alias '%s' is deprecated, use the real name '%s'.\n   @%s\n", name, realname, caller)
			end

			-- is there an options table?
			local options = nil
			if type(version) == 'table' then
				options = version
				version = options.version
				options.version = nil
			end

			if not wks.package_cache[realname] then
				local pkg = __importPackage(realname, version)
				__setPackageOptions(pkg, options)
				table.insert(init_table, pkg)

				wks.package_cache[realname] = pkg
				for _, alias in ipairs(aliases) do
					verbosef("ALIAS: '%s' aliased to '%s'.", realname, alias)
					wks.package_cache[alias] = pkg
					__aliases[alias] = realname
				end
			else
				p.warn("Package '%s' already imported.", realname)
			end
		end

		-- setup a filter with the action and system 'filters', we don't know the rest yet.
		local filter = {
			action = _ACTION,
			system = os.getSystemTags(os.target()),
		}

		-- load all variants that match the filter.
		for _, pkg in ipairs(init_table) do
			pkg:loadvariants(filter)
		end

		-- initialize.
		for _, pkg in ipairs(init_table) do
			if not __loaded[pkg.name] then
				__loaded[pkg.name] = true
			else
				p.api._isIncludingExternal = true
			end

			-- and initialize all loaded variants.
			pkg:initialize()

			p.api._isIncludingExternal = nil
		end

		-- restore 'group' function.
		_G['group'] = groupFunc

		-- restore current scope.
		p.api.scope.current = scope
	end


---
-- Get a package by name from the current workspace.
---
	function pm.getPackage(name)
		local wks = p.api.scope.workspace
		if wks == nil then
			error("No workspace in scope.", 3)
		end

		local realname = __aliases[name:lower()]
		if realname ~= nil then
			p.warn("Using the alias '%s' is deprecated, use the real name '%s'.", name, realname)
		end

		return wks.package_cache[name:lower()]
	end


---
-- Get an option for a package.
---
	function pm.getPackageOption(name, option)
		local pkg

		if option == nil then
			local project = p.api.scope.project or prj
			if project == nil then
				error("No project in scope.", 3)
			end

			option = name
			pkg    = project.package
		else
			local realname = __getRealname(name):lower()
			pkg = pm.getPackage(realname)
		end

		if pkg == nil then
			p.error("Package options can't be read.", 3)
		end

		return pkg.optionValues[option]
	end

---
-- Resets the state of the package manager to it's default state.
---
	function pm.reset()
		__loaded = {}
		pm.cache_location    = nil
		pm.folders           = {}
		pm.aliases           = {}
		pm.servers           = {
			'http://***REMOVED***',
			'http://***REMOVED***'
		}
	end


---
-- override 'workspace' so that we can initialize a package cache.
---
	p.override(p.workspace, 'new', function(base, name)
		local wks = base(name)
		wks.package_cache   = wks.package_cache or {}
		return wks
	end)


---
-- override 'context.compile' so that we can inject the package options into the filters
---
	p.override(p.context, 'compile', function(base, ctx)
		-- if this is a project and it was generated from a package, inject package options
		-- into filter context.
		local prj = ctx.project
		if prj ~= nil and prj.frompackage then
			for name, value in pairs(prj.package.optionValues) do
				p.context.addFilter(ctx, name, value)
			end
		end

		return base(ctx)
	end)


---
-- private callback for the package targetdir.
---
	function pm._selectTargetDir(cfg)
		if cfg.kind == 'StaticLib' then
			return cfg.package_libdir
		else
			return cfg.package_bindir
		end
	end

	function pm._printPackageOptions(pkg)
		if not pkg.options then
			return
		end
		printf('  Package: %s-%s', pkg.name, pkg.version)
		printf('  --------------------------')

		local k_length = 0
		local n_length = 0
		for name, f in pairs(pkg.options) do
			if (#f.kind > k_length) then k_length = #f.kind end
			if (#name > n_length) then n_length = #name end
		end

		local fmt = "  %-" .. k_length .. "s %-" .. n_length .. "s %s %s"
		for name, f in spairs(pkg.options) do
			local k = string.format("%-" .. k_length .. "s", f.kind)
			local n = string.format("%-" .. n_length .. "s", name)
			local r = iif(f.required, "[required]", "[optional]")

			if f.default ~= nil then
				printf("  %s %s (default: %s) %s", k, n, tostring(f.default), f.description or '');
			else
				printf("  %s %s %s %s", k, n, r, f.description or '');
			end
		end
	end

---
-- override 'project' so that when a package defines a new project we initialize it with some default values.
---
	p.override(p.project, 'new', function(base, name, parent)
		local prj = base(name, parent)

		if not prj.package then
			if package.current then
				-- set package on project.
				prj.package = package.current.package
				prj.variant = package.current
				prj.frompackage = true

				-- set some default package values.
				prj.blocks[1].targetdir = "%{premake.packagemanager._selectTargetDir(cfg)}"
				prj.blocks[1].objdir    = "%{cfg.package_objdir}/" .. name
				prj.blocks[1].buildlog  = "%{cfg.package_buildlog}"
				prj.blocks[1].location  = "%{prj.package_location}"

			elseif parent ~= nil then
				name = name:lower()
				local p = parent.package_cache[name]
				if p then
					error("Package '" .. name .. "' already exists in the workspace.")
				end

				-- set package on project.
				prj.package = m.createProjectPackage(name)
				parent.package_cache[name] = prj.package
			end

			-- add project to package.
			table.insert(prj.package.projects, prj)
		end

		return prj
	end)


---
-- Set metatable on global package manager, locking it down.
---
	setmetatable(pm, {
		__metatable = false,

		__index = function(tbl, key)
			return rawget(tbl, key)
		end,

		__newindex = function(tbl, key, value)
			if (key == "cache_location") then
				assert(value == nil or type(value) == "string", "cache_location must be a string or nil.")
				rawset(tbl, key, value)
			elseif (key == "folders") then
				assert(type(value) == "table", "folders must be a table.")
				rawset(tbl, key, value)
			elseif (key == "servers") then
				assert(type(value) == "table", "servers must be a table.")
				rawset(tbl, key, value)
			elseif (key == "aliases") then
				assert(type(value) == "table", "aliases must be a table.")
				rawset(tbl, key, value)
			else
				error("Attempt to modify packagemanager field: " .. key)
			end
		end,

		__tostring = function()
			return "Package Manager"
		end,
	})


---
--- inject lockfile store into p.main.preBake
---
	p.override(p.main, "postBake", function (base)
		-- write the lockfile.
		local g = p.api.rootContainer()
		local fn = g.lockfile or path.join(_MAIN_SCRIPT_DIR, ".lockfile")

		if g.__lockfile ~= nil then
			local lockfile = json.encode_pretty(g.__lockfile)
			if #lockfile > 2 then
				os.mkdir(path.getdirectory(fn))
				local f, err = os.writefile_ifnotequal(lockfile, fn);
			else
				os.remove(fn)
			end
		else
			os.remove(fn)
		end

		-- now run the prebake.
		base()
	end)


---
--- provide help for package options.
---
	p.override(p.main, 'processCommandLine', function(base)
		if (_OPTIONS["package-help"]) then
			print('Package options:')
			print();
			for wks in p.global.eachWorkspace() do
				printf('Workspace: %s', wks.name)
				printf('--------------------------')
				for name, pkg in pairs(wks.package_cache) do
					if not __aliases[name] then
						pm._printPackageOptions(pkg)
					end
				end
			end
			print('--------------------------')
			print('done.');
			os.exit(1)
		end
		base()
	end)


-- return the module pointer.
return p.modules.packagemanager
