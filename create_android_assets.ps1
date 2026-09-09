$compress = @{
LiteralPath= "init.lua", "data", "modules", "layouts", "mods"
CompressionLevel = "Fastest"
DestinationPath = "android\otclientv8\assets\data.zip"
}
Compress-Archive @compress -Force

python tools\validate_package.py $compress.DestinationPath
if ($LASTEXITCODE -ne 0) {
    throw "Android data.zip validation failed."
}
