local p            = premake
p.extensions.cmake = { _VERSION = "1.0.0" }

newaction({
	-- Metadata
	trigger     = "cmake",
	shortname   = "CMake",
	description = "Generate CMake files",
	toolset     = "clang",
	
	-- Capabilities
	valid_kinds     = { "ConsoleApp", "WindowedApp", "Makefile", "SharedLib", "StaticLib", "Utility" },
	valid_languages = { "C", "C++" },
	valid_tools     = { "gcc", "clang", "msc" },
	
	-- Workspace generation
	onWorkspace = function(wks)
		p.generate(wks, "CMakeLists.txt", p.extensions.cmake.generateWorkspace)
	end,
	
	-- Project generation
	onProject = function(prj)
		if prj.kind == "Utility" then return end
		p.generate(prj, ".cmake", p.extensions.cmake.generateProject)
	end
})

--
-- Decide when the full module should be loaded.
--
return function(cfg)
	return _ACTION == "cmake"
end