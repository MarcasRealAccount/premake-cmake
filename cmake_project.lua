local p         = premake
local project   = p.project
local workspace = p.workspace
local tree      = p.tree
local cmake     = p.extensions.cmake
cmake.project   = {}
local m         = cmake.project

m.props = function(prj)
	return {
		m.kind,
		m.files,
		m.configs
	}
end

function cmake.generateProject(prj)
	p.indent("\t")
	
	local oldGetDefaultSeparator = path.getDefaultSeparator
	path.getDefaultSeparator     = function() return "/" end
	
	p.callArray(m.props, prj)
	
	path.getDefaultSeparator = oldGetDefaultSeparator
end

function m.kind(prj)
	if prj.kind == "StaticLib" then
		p.push("add_library(\"%s\" STATIC", prj.name)
	elseif prj.kind == "SharedLib" then
		p.push("add_library(\"%s\" SHARED", prj.name)
	else
		if prj.executable_suffix then
			p.w("set(CMAKE_EXECUTABLE_SUFFIX \"%s\")", prj.executable_suffix)
		end
		p.push("add_executable(\"%s\"", prj.name)
	end
end

function m.files(prj)
	local tr = project.getsourcetree(prj)
	tree.traverse(tr, {
		onleaf = function(node, depth)
			p.w("\"%s\"", path.getrelative(prj.workspace.location, ndoe.abspath))
			
			for cfg in project.eachconfig(prj) do
				local filecfg = p.fileconfig.getconfig(node, cfg)
				local rule    = p.global.getRuleForFile(node.name, prj.rules)
				
				if p.fileconfig.hasFileSettings(filecfg) then
					for _, output in ipairs(filecfg.buildOutputs) do
						p.w("\"%s\"", path.getrelative(prj.workspace.location, output))
					end
					break
				elseif rule then
					local environ = table.shallowcopy(filecfg.environ)
					
					if rule.propertydefinition then
						p.rule.prepareEnvironment(rule, environ, cfg)
						p.rule.prepareEnvironment(rule, environ, filecfg)
					end
					local rulecfg = p.context.extent(rule, environ)
					for _, output in ipairs(rulecfg.buildOutputs) do
						p.w("\"%s\"", path.getrelative(prj.workspace.location, output))
					end
					break
				end
			end
		end
	}, true)
	p.pop(")")
end

m.configProps = function(prj, cfg)
	return {
		m.dependencies,
		m.outputDirs,
		m.includeDirs,
		m.defines,
		m.libDirs,
		m.libs,
		m.buildOptions,
		m.linkOptions,
		m.compileOptions,
		m.cppStandard,
		m.pch,
		m.prebuildCommands,
		m.postbuildCommands,
		m.prelinkCommands,
		m.customCommands
	}
end

function m.configs(prj)
	for cfg in project.eachconfig(prj) do
		p.push("if(CMAKE_BUILD_TYPE STREQUAL \"%s\")", cmake.common.configName(cfg, #prj.workspace.platforms > 1))
		p.callArray(m.configProps, prj, cfg)
		p.pop("endif()")
	end
end

function m.dependencies(prj, cfg)
	local dependencies = project.getdependencies(prj, cfg)
	if #dependencies > 0 then
		p.push("add_dependencies(\"%s\"", prj.name)
		for _, dependency in ipairs(dependencies) do
			p.w("\"%s\"", dependency.name)
		end
		p.pop(")")
	end
end

function m.outputDirs(prj, cfg)
	p.push("set_target_properties(\"%s\" PROPERTIES", prj.name)
	p.w("OUTPUT_NAME \"%s\"", cfg.buildtarget.basename)
	p.w("ARCHIVE_OUTPUT_DIRECTORY \"%s\"", path.getrelative(prj.workspace.location, cfg.buildtarget.directory))
	p.w("LIBRARY_OUTPUT_DIRECTORY \"%s\"", path.getrelative(prj.workspace.location, cfg.buildtarget.directory))
	p.w("RUNTIME_OUTPUT_DIRECTORY \"%s\"", path.getrelative(prj.workspace.location, cfg.buildtarget.directory))
	p.pop(")")
end

function m.includeDirs(prj, cfg)
	if #cfg.sysincludedirs > 0 then
		p.push("target_include_directories(\"%s\" SYSTEM PRIVATE", prj.name)
		for _, includedir in ipairs(cfg.sysincludedirs) do
			p.w("\"%s\"", includedir)
		end
		p.pop(")")
	end
	
	if #cfg.includedirs > 0 then
		p.push("target_include_directories(\"%s\" PRIVATE", prj.name)
		for _, includedir in ipairs(cfg.includedirs) do
			p.w("\"%s\"", includedir)
		end
		p.pop(")")
	end
	
	if #cfg.forceincludes > 0 then
		p.push("if (MSVC)")
		p.w("target_compile_options(\"%s\" PRIVATE %s)", prj.name, table.implode(p.tools.msc.getforceincludes(cfg), "", "", " "))
		p.pop()
		p.push("else()")
		p.w("target_compile_options(\"%s\" PRIVATE %s)", prj.name, table.implode(p.tools.gcc.getforceincludes(cfg), "", "", " "))
		p.pop("endif()")
	end
end

function m.defines(prj, cfg)
	if #cfg.defines > 0 then
		p.push("target_compile_definitions(\"%s\" PRIVATE", prj.name)
		for _, define in ipairs(cfg.defines) do
			p.w("%s", p.esc(define):gsub(" ", "\\ "))
		end
		p.pop(")")
	end
end

function m.libDirs(prj, cfg)
	if #cfg.libdirs > 0 then
		p.push("target_link_directories(\"%s\" PRIVATE", prj.name)
		for _, libdir in ipairs(cfg.libdirs) do
			p.w("\"%s\"", libdir)
		end
		p.pop(")")
	end
end

function m.libs(prj, cfg)
	local uselinkgroups = isclangorgcc and cfg.linkgroups == p.ON
	if uselinkgroups or #config.getlinks(cfg, "dependencies", "object") > 0 or #config.getlinks(cfg, "system", "fullpath") > 0 then
		p.push("target_link_libraries(\"%s\"", prj.name)
		if uselinkgroups then
			p.w("-Wl,--start-group")
		end
		for a, link in ipairs(config.getlinks(cfg, "dependencies", "object")) do
			p.w("\"%s\"", link.project.name)
		end
		if uselinkgroups then
			p.w("-Wl,--end-group")
			p.w("-Wl,--start-group")
		end
		for _, link in ipairs(config.getlinks(cfg, "system", "fullpath")) do
			if cmake.common.isFramework(link) then
				p.w("\"-framework %s\"", cmake.common.getFrameworkName(link))
			else
				p.w("\"%s\"", link)
			end
		end
		if uselinkgroups then
			p.w("-Wl,--end-group")
		end
		p.pop(")")
	end
end

function m.buildOptions(prj, cfg)
	local options = ""
	for _, option in ipairs(cfg.buildoptions) do
		options = options .. option .. " "
	end
	if options:len() > 0 then
		p.w("set_target_properties(\"%s\" PROPERTIES COMPILE_FLAGS %s)", prj.name, options)
	end
end

function m.linkOptions(prj, cfg)
	local options = ""
	for _, option in ipairs(cfg.linkoptions) do
		options = options .. option .. " "
	end
	if options:len() > 0 then
		p.w("set_target_properties(\"%s\" PROPERTIES LINK_FLAGS %s)", prj.name, options)
	end
end

function m.compileOptions(prj, cfg)
	local toolset = cmake.common.getCompiler(cfg)
	if #toolset.getcflags(cfg) > 0 or #toolset.getcxxflags(cfg) > 0 then
		p.push("target_compile_options(\"%s\" PRIVATE", prj.name)
		for _, flag in ipairs(toolset.getcflags(cfg)) do
			p.w("$<$<AND:$<CONFIG:%s>,$<COMPILE_LANGUAGE:C>>:%s>", cmake.common.configName(cfg), flag)
		end
		for _, flag in ipairs(toolset.getcxxflags(cfg)) do
			p.w("$<$<AND:$<CONFIG:%s>,$<COMPILE_LANGUAGE:CXX>>:%s>", cmake.common.configName(cfg), flag)
		end
		p.pop(")")
	end
end

function m.cppStandard(prj, cfg)
	if (cfg.cppdialect and cfg.cppdialect:len() > 0) or cfg.cppdialect == "Default" then
		local extensions = iif(cfg.cppdialect:find("^gnu") == nil, "NO", "YES")
		local pic        = iif(cfg.pic == "On", "True", "False")
		local lto        = iif(cfg.flags.LinkTimeOptimization, "True", "False")
		
		p.push("set_target_properties(\"%s\" PROPERTIES", prj.name)
		p.w("CXX_STANDARD %s", cmake.common.cppStandards[cfg.cppdialect])
		p.w("CXX_STANDARD_REQUIRED YES")
		p.w("CXX_EXTENSIONS %s", extensions)
		p.w("POSITION_INDEPENDENT_CODE %s", pic)
		p.w("INTERPROCEDURAL_OPTIMIZATION %s", lto)
		p.pop(")")
	end
end

function m.pch(prj, cfg)
	if not cfg.flags.NoPCH and cfg.pchheader then
		local pch   = cfg.pchheader
		local found = false
		
		local testname = path.join(cfg.workspace.basedir, pch)
		if os.isfile(testname) then
			pch   = project.getrelative(cfg.workspace, testname)
			found = true
		else
			for _, incdir in ipairs(cfg.includedirs) do
				testname = path.join(incdir, pch)
				if os.isfile(testname) then
					pch   = project.getrelative(cfg.workspace, testname)
					found = true
					break
				end
			end
		end
		
		if not found then
			pch = project.getrelative(cfg.workspace, path.getabsolute(pch))
		end
		
		p.w("target_precompile_headers(\"%s\" PRIVATE \"%s\")", prj.name, path.getabsolute(pch))
	end
end

function m.prebuildCommands(prj, cfg)
	if cfg.prebuildmessage or #cfg.prebuildcommands > 0 then
		p.push("add_custom_target(prebuild-%s", prj.name)
		if cfg.prebuildmessage then
			p.w("COMMAND %s", cmake.common.fixSingleQuotes(os.translateCommandsAndPaths("{ECHO} " .. cfg.prebuildmessage, cfg.project.basedir, cfg.project.location)))
		end
		for _, command in ipairs(cmake.common.fixSingleQuotes(os.translateCommandsAndPaths(cfg.prebuildcommands, cfg.project.basedir, cfg.project.location))) do
			p.w("COMMAND %s", command)
		end
		p.pop(")")
		p.w("add_dependencies(\"%s\" prebuild-%s)", prj.name, prj.name)
	end
end

function m.postbuildCommands(prj, cfg)
	if cfg.postbuildmessage or #cfg.postbuildcommands > 0 then
		p.push("add_custom_target(postbuild-%s", prj.name)
		if cfg.postbuildmessage then
			p.w("COMMAND %s", cmake.common.fixSingleQuotes(os.translateCommandsAndPaths("{ECHO} " .. cfg.postbuildmessage, cfg.project.basedir, cfg.project.location)))
		end
		for _, command in ipairs(cmake.common.fixSingleQuotes(os.translateCommandsAndPaths(cfg.postbuildcommands, cfg.project.basedir, cfg.project.location))) do
			p.w("COMMAND %s", command)
		end
		p.pop(")")
		p.w("add_dependencies(\"%s\" postbuild-%s)", prj.name, prj.name)
	end
end

function m.prelinkCommands(prj, cfg)
	if cfg.prelinkmessage or #cfg.prelinkcommands > 0 then
		p.push("add_custom_command(TARGET \"%s\"", prj.name)
		p.w("PRE_LINK")
		for _, command in ipairs(cmake.common.fixSingleQuotes(os.translateCommandsAndPaths(cfg.prelinkcommands, cfg.project.basedir, cfg.project.location))) do
			p.w("COMMAND %s", command)
		end
		p.pop(")")
	end
end

local function addCustomCommand(fileconfig, filename)
	if #fileconfig.buildcommands == 0 or #fileconfig.buildOutputs == 0 then
		return
	end
	
	p.push("add_custom_command(TARGET OUTPUT %s", table.implode(project.getrelative(cfg.project, fileconfig.buildOutputs), "", "", " "))
	if fileconfig.buildmessage then
		p.w("COMMAND %s", cmake.common.fixSingleQuotes(os.translateCommandsAndPaths("{ECHO} " .. fileconfig.buildmessage, cfg.project.basedir, cfg.project.location)))
	end
	for _, command in ipairs(cmake.common.fixSingleQuotes(os.translateCommandsAndPaths(fileconfig.buildCommands, cfg.project.basedir, cfg.project.location))) do
		p.w("COMMAND %s", command)
	end
	if filename:len() > 0 and #fileconfig.buildInputs > 0 then
		filename = filename .. " "
	end
	if filename:len() > or #fileconfig.buildInputs > 0 then
		p.w("DEPENDS %s", filename .. table.implode(fileconfig.buildInputs, "", "", " "))
	end
	p.pop(")")
end

function m.customCommands(prj, cfg)
	local tr = project.getsourcetree(prj)
	p.tree.traverse(tr, {
		onleaf = function(node, depth)
			local filecfg = p.fileconfig.getconfig(node, cfg)
			local rule    = p.global.getRuleForFile(node.name, prj.rules)
			
			if p.fileconfig.hasFileSettings(filecfg) then
				addCustomCommand(filecfg, node.relpath)
			elseif rule then
				local environ = table.shallowcopy(filecfg.environ)
				
				if rule.propertydefinition then
					p.rule.prepareEnvironment(rule, environ, cfg)
					p.rule.prepareEnvironment(rule, environ, filecfg)
				end
				local rulecfg = p.context.extent(rule, environ)
				addCustomCommand(rulecfg, node.relpath)
			end
		end
	})
	addCustomCommand(cfg, "")
end