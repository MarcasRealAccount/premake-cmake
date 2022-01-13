local p = premake

-- Include source files manually if not embedded
for _, file in ipairs(dofile("_manifest.lua")) do
	include(file)
end