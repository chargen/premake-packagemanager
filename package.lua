---
-- Package management module
-- Legacy "Package" API.
-- Copyright (c) 2014-2017 Blizzard Entertainment
---

local p = premake
local m = p.modules.packagemanager

package = package or {}

---
-- get a previously imported package by name.
---
	function package.get(name)
		local result = p.packagemanager.getPackage(name)
		if not result then
			p.error("Package was not imported; use 'import { ['" .. name .. "'] = 'version' }'.")
		end
		return result
	end

---
-- See if a previously imported package was imported.
---
	function package.isimported(name)
		return p.packagemanager.getPackage(name) ~= nil
	end


---
-- check package version. Comparisions take the form of ">=5.0" (5.0 or later),
-- "5.0" (5.0 or later), ">=5.0 <6.0" (5.0 or later but not 6.0 or later).
---
	function package.require(name, checks)
		local pkg = p.packagemanager.getPackage(name)
		if pkg == nil then
			p.error("Package was not imported; use 'import { ['" .. name .. "'] = 'version' }'.")
		end

		if not p.checkVersion(pkg.version, checks) then
			p.error("Package version '" .. pkg.version .. "' does not meet '" .. checks .. "' requirement.")
		end
	end


---
-- Import a set of packages.
---
	function import(tbl)
		if package.current then
			p.error('Packages cannot import other package, only the top-level workspace can do that')
		end

		return p.packagemanager.import(tbl)
	end


---
-- Get an option for a package.
---
	function getpackageoption(name, option)
		return p.packagemanager.getPackageOption(name, option)
	end


---
-- Execute all test scripts
---
	function includePackageTests()
		local wks = p.api.scope.workspace
		if wks == nil then
			p.error("No workspace in scope.", 3)
		end

		-- go through each variant that is loaded, and execute the initializer.
		for name, pkg in pairs(wks.package_cache) do
			-- don't process aliases.
			if name == pkg.name then
				pkg:includeTests()
			end
		end
	end

