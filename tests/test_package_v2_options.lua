local suite = test.declare("package_v2_options")

local p        = premake
local pm       = p.packagemanager
local test_dir = os.getcwd()

--
-- Setup
--
	local wks, prj, cfg

	function suite.setup()
		p.packagemanager.reset()
		p.packagemanager.folders = { path.join(test_dir, "test_packages") }
		p.packagemanager.servers = { }

		wks = test.createWorkspace()
	end

	local function prepare()
		wks = test.getWorkspace(wks)
		prj = test.getproject(wks, 2)
		cfg = test.getconfig(prj, "Debug")
	end

--
-- Test not setting options.
--
	function suite.no_options_set()
		import { ['v2'] = 'options' }
		prepare()

		test.isequal(2, #cfg.defines)
		test.contains({ "MULTITHREADING=0", "STACKSIZE=1024" }, cfg.defines)
	end

--
-- Test setting option to a value.
--
	function suite.options_set_on()
		import {
			['v2'] = {
				version = 'options',
				multithreading = 'on'
			}
		}

		prepare()

		test.isequal(2, #cfg.defines)
		test.contains({ "MULTITHREADING=1", "STACKSIZE=1024" }, cfg.defines)
	end

--
-- Test setting option to a value.
--
	function suite.options_set_off()
		import {
			['v2'] = {
				version = 'options',
				multithreading = 'off'
			}
		}
		prepare()

		test.isequal(2, #cfg.defines)
		test.contains({ "MULTITHREADING=0", "STACKSIZE=1024" }, cfg.defines)
	end


--
-- Test stacksize option
--
	function suite.options_set_stacksize()
		import {
			['v2'] = {
				version = 'options',
				stacksize = 4096
			}
		}
		prepare()

		test.isequal(2, #cfg.defines)
		test.contains({ "MULTITHREADING=0", "STACKSIZE=4096" }, cfg.defines)
	end


--
-- Test use exported defines option
--
	function suite.use_options_define_boolean_off()
		import {
			['v2'] = {
				version = 'options',
				multithreading = 'off'
			}
		}

		local prj = project 'useV2'
			includedependencies { 'v2' }

		local cfg = test.getconfig(prj, "Debug")

		test.isequal(1, #cfg.defines)
		test.contains({ "BC_STACK_SIZE=1024" }, cfg.defines)
	end

--
-- Test use exported defines option
--
	function suite.use_options_define_boolean_on()
		import {
			['v2'] = {
				version = 'options',
				multithreading = 'on'
			}
		}

		local prj = project 'useV2'
			includedependencies { 'v2' }

		local cfg = test.getconfig(prj, "Debug")

		test.isequal(2, #cfg.defines)
		test.contains({ "BC_ENABLE_MULTITHREADING", "BC_STACK_SIZE=1024" }, cfg.defines)
	end

--
-- Test use exported defines option
--
	function suite.use_options_define_value()
		import {
			['v2'] = {
				version = 'options',
				stacksize = 4096
			}
		}

		local prj = project 'useV2'
			includedependencies { 'v2' }

		local cfg = test.getconfig(prj, "Debug")

		test.isequal(1, #cfg.defines)
		test.contains({ "BC_STACK_SIZE=4096" }, cfg.defines)
	end

