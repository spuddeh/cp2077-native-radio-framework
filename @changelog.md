# Changelog - Native Radio Framework

## [0.1.0] - 2026-09-07

### Added
- RED4ext plugin that extends the engine's compiled radio station roster, so a custom station is a
  real station rather than a separate player.
- Vehicle receiver bound raised, so a custom station can be selected in a car.
- Station manifests discovered from `red4ext/plugins/NativeRadioFramework/stations/<Mod>/station.json`.
- Redscript service that registers each station's metadata entry and its membership of the station
  map at runtime.

### Notes
- Nothing vanilla is replaced. No archive ships, so station mods cannot conflict with each other.
