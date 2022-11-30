local p         = premake
local project   = p.project
local workspace = p.workspace
local tree      = p.tree
local config    = p.config
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
	prj.__cmake                = {}
	prj.__cmake.files          = {}
	prj.__cmake.generatedFiles = {}
	prj.__cmake.fileLangs      = {}
	prj.__cmake.customCommands = {}
	local timer = cmake.common.createTimer("p.extensions.cmake.generateProject", { prj.name })
	p.indent("\t")
	
	local oldGetDefaultSeparator = path.getDefaultSeparator
	path.getDefaultSeparator     = function() return "/" end
	
	p.callArray(m.props, prj)
	
	path.getDefaultSeparator = oldGetDefaultSeparator
	timer.stop()
end

function m.kind(prj)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.kind", { prj.name })
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
	timer.stop()
end

function m.files(prj)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.files", { prj.name })
	local tr = project.getsourcetree(prj)
	tree.traverse(tr, {
		onleaf = function(node, depth)
			table.insert(prj.__cmake.files, node.abspath)

			if node.configs then
				for cfg in project.eachconfig(prj) do
					local filecfg = p.fileconfig.getconfig(node, cfg)
					local rule    = p.global.getRuleForFile(node.name, prj.rules)

					if filecfg.compileas then
						if not prj.__cmake.fileLangs[filecfg.compileas] then prj.__cmake.fileLangs[filecfg.compileas] = {} end
						local fileLang = prj.__cmake.fileLangs[filecfg.compileas]
						fileLang[node.abspath] = filecfg
					end

					if p.fileconfig.hasFileSettings(filecfg) then
						for _, output in ipairs(filecfg.buildOutputs) do
							table.insert(prj.__cmake.files, output)
							table.insert(prj.__cmake.generatedFiles, output)
						end
						table.insert(prj.__cmake.customCommands, {
							cfg     = filecfg,
							relpath = node.relpath
						})
						break
					elseif rule then
						local environ = table.shallowcopy(filecfg.environ)

						if rule.propertydefinition then
							p.rule.prepareEnvironment(rule, environ, cfg)
							p.rule.prepareEnvironment(rule, environ, filecfg)
						end
						local rulecfg = p.context.extent(rule, environ)
						for _, output in ipairs(rulecfg.buildOutputs) do
							table.insert(prj.__cmake.files, output)
							table.insert(prj.__cmake.generatedFiles, output)
						end
						table.insert(prj.__cmake.customCommands, {
							cfg     = rulecfg,
							relpath = node.relpath
						})
						break
					end
				end
			end
		end
	}, true)

	for _, v in ipairs(prj.__cmake.files) do
		p.w("\"%s\"", v)
	end
	p.pop(")")
	timer.stop()
end

m.configProps = function(prj, cfg)
	return {
		m.dependencies,
		m.sourceFileProperties,
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
	local timer = cmake.common.createTimer("p.extensions.cmake.project.configs", { prj.name })
	for cfg in project.eachconfig(prj) do
		p.push("if(CMAKE_BUILD_TYPE STREQUAL \"%s\")", cmake.common.configName(cfg, #prj.workspace.platforms > 1))
		p.callArray(m.configProps, prj, cfg)
		p.pop("endif()")
	end
	timer.stop()
end

function m.dependencies(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.dependencies", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
	local dependencies = project.getdependencies(prj, cfg)
	if #dependencies > 0 then
		p.push("add_dependencies(\"%s\"", prj.name)
		for _, dependency in ipairs(dependencies) do
			p.w("\"%s\"", dependency.name)
		end
		p.pop(")")
	end
	timer.stop()
end

function m.sourceFileProperties(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.sourceFileProperties", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
	p.push("set_source_files_properties(")
	for _, v in ipairs(prj.__cmake.generatedFiles) do
		p.w("\"%s\"", v)
	end
	p.w("PROPERTIES")
	p.w("GENERATED true")
	p.pop(")")

	for lang, files in pairs(prj.__cmake.fileLangs) do
		if not cmake.common.compileasLangs[lang] then
			error("CMake generator does not support compileas langauge " .. lang .. "!")
		end
		p.push("set_source_files_properties(")
		for path, file in pairs(files) do
			p.w("\"%s\"", path)
		end
		p.w("PROPERTIES")
		p.w("LANGUAGE %s", cmake.common.compileasLangs[lang])
		p.pop(")")
	end
	timer.stop()
end

function m.outputDirs(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.outputDirs", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
	p.push("set_target_properties(\"%s\" PROPERTIES", prj.name)
	p.w("OUTPUT_NAME \"%s\"", cfg.buildtarget.basename)
	p.w("ARCHIVE_OUTPUT_DIRECTORY \"%s\"", cfg.buildtarget.directory)
	p.w("LIBRARY_OUTPUT_DIRECTORY \"%s\"", cfg.buildtarget.directory)
	p.w("RUNTIME_OUTPUT_DIRECTORY \"%s\"", cfg.buildtarget.directory)
	p.pop(")")
	timer.stop()
end

function m.includeDirs(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.includeDirs", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
	if #cfg.sysincludedirs > 0 then
		p.push("target_include_directories(\"%s\" SYSTEM PRIVATE", prj.name)
		for _, includedir in ipairs(cfg.sysincludedirs) do
			p.w("\"%s\"", includedir)
		end
		p.pop(")")
	end

	if #cfg.externalincludedirs > 0 then
		p.push("target_include_directories(\"%s\" SYSTEM PRIVATE", prj.name)
		for _, includedir in ipairs(cfg.externalincludedirs) do
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

	timer.stop()
end

function m.defines(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.defines", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
	if #cfg.defines > 0 then
		p.push("target_compile_definitions(\"%s\" PRIVATE", prj.name)
		for _, define in ipairs(cfg.defines) do
			p.w("%s", p.esc(define):gsub(" ", "\\ "))
		end
		p.pop(")")
	end
	timer.stop()
end

function m.libDirs(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.libDirs", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
	if #cfg.libdirs > 0 then
		p.push("target_link_directories(\"%s\" PRIVATE", prj.name)
		for _, libdir in ipairs(cfg.libdirs) do
			p.w("\"%s\"", libdir)
		end
		p.pop(")")
	end
	timer.stop()
end

function m.libs(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.libs", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
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
	timer.stop()
end

function m.buildOptions(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.buildOptions", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
	local options = ""
	for _, option in ipairs(cfg.buildoptions) do
		options = options .. option .. "\n"
	end
	if options:len() > 0 then
		p.push("target_compile_options(\"%s\" PRIVATE", prj.name)
		p.w(options)
		p.pop(")")
	end
	timer.stop()
end

function m.linkOptions(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.linkOptions", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
	local toolset = cmake.common.getCompiler(cfg)
	local ldflags = toolset.getldflags(cfg)
	local options = ""
	for _, option in ipairs(cfg.linkoptions) do
		options = options .. option .. " "
	end
	for _, flag in ipairs(ldflags) do
		options = options .. flag .. " "
	end
	if options:len() > 0 then
		p.w("set_target_properties(\"%s\" PROPERTIES LINK_FLAGS %s)", prj.name, options)
	end
	timer.stop()
end

function m.compileOptions(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.compileOptions", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
	local toolset       = cmake.common.getCompiler(cfg)
	local cflags        = toolset.getcflags(cfg)
	local cxxflags      = toolset.getcxxflags(cfg)
	local forceIncludes = toolset.getforceincludes(cfg)
	if #cflags > 0 or #cxxflags > 0 then
		p.push("target_compile_options(\"%s\" PRIVATE", prj.name)
		for _, flag in ipairs(cflags) do
			p.w("$<$<COMPILE_LANGUAGE:C>:%s>", flag)
		end
		for _, flag in ipairs(cxxflags) do
			p.w("$<$<COMPILE_LANGUAGE:CXX>:%s>", flag)
		end
		for _, flag in ipairs(forceIncludes) do
			p.w("$<$<COMPILE_LANGUAGE:C>:%s>", flag)
			p.w("$<$<COMPILE_LANGUAGE:CXX>:%s>", flag)
		end
		p.pop(")")
	end
	timer.stop()
end

function m.cppStandard(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.cppStandard", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
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
	timer.stop()
end

function m.pch(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.pch", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
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
	timer.stop()
end

function m.prebuildCommands(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.prebuildCommands", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
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
	timer.stop()
end

function m.postbuildCommands(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.postbuildCommands", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
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
	timer.stop()
end

function m.prelinkCommands(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.prelinkCommands", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
	if cfg.prelinkmessage or #cfg.prelinkcommands > 0 then
		p.push("add_custom_command(TARGET \"%s\"", prj.name)
		p.w("PRE_LINK")
		for _, command in ipairs(cmake.common.fixSingleQuotes(os.translateCommandsAndPaths(cfg.prelinkcommands, cfg.project.basedir, cfg.project.location))) do
			p.w("COMMAND %s", command)
		end
		p.pop(")")
	end
	timer.stop()
end

local function addCustomCommand(cfg, fileconfig, filename)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.addCustomCommand")
	if #fileconfig.buildcommands == 0 or #fileconfig.buildOutputs == 0 then
		return
	end
	
	p.push("add_custom_command(TARGET OUTPUT %s", table.implode(fileconfig.buildOutputs, "", "", " "))
	if fileconfig.buildmessage then
		p.w("COMMAND %s", cmake.common.fixSingleQuotes(os.translateCommandsAndPaths("{ECHO} " .. fileconfig.buildmessage, cfg.project.basedir, cfg.project.location)))
	end
	for _, command in ipairs(cmake.common.fixSingleQuotes(os.translateCommandsAndPaths(fileconfig.buildCommands, cfg.project.basedir, cfg.project.location))) do
		p.w("COMMAND %s", command)
	end
	if filename:len() > 0 then
		filename = cfg.project.location .. "/" .. filename
		if #fileconfig.buildInputs > 0 then
			filename = filename .. " "
		end	
	end
	if filename:len() > 0 or #fileconfig.buildInputs > 0 then
		p.w("DEPENDS %s", filename .. table.implode(fileconfig.buildInputs, "", "", " "))
	end
	p.pop(")")
	timer.stop()
end

function m.customCommands(prj, cfg)
	local timer = cmake.common.createTimer("p.extensions.cmake.project.customCommands", { prj.name, cmake.common.configName(cfg, #prj.workspace.platforms > 1) })
	for _, v in ipairs(prj.__cmake.customCommands) do
		addCustomCommand(cfg, v.cfg, v.relpath)
	end
	addCustomCommand(cfg, cfg, "")
	timer.stop()
end
