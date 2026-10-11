-- Macaroon OS manifest
-- Single source of truth for updater. Installer hardcodes the same list
-- as bootstrap (it can't download this before knowing what to download).
return {
  "startup.lua",
  "update.lua",
  "macaroon/version.lua",
  "macaroon/manifest.lua",
  "macaroon/updater.lua",
  "macaroon/window.lua",
  "macaroon/desktop.lua",
  "macaroon/apps/hello.lua",
  "macaroon/apps/about.lua",
  "macaroon/apps/update.lua",
}
