project 'v2'
	kind 'StaticLib'

	filter { 'multithreading:true' }
		defines { 'MULTITHREADING=1'}

	filter { 'multithreading:false' }
		defines { 'MULTITHREADING=0'}

	filter {}

	defines {
		'STACKSIZE=%{getpackageoption("stacksize") or 1024}'
	}


	if getpackageoption("stacksize") then
	end
