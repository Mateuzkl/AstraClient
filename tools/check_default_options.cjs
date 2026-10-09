'use strict';
const fs = require('node:fs');
const path = require('node:path');
function validateDefaultOptions(raw) {
  const bytes = Buffer.isBuffer(raw) ? raw : Buffer.from(raw);
  if (bytes.length < 32768) throw new Error('default-options.json is unexpectedly small: ' + bytes.length);
  let data;
  try { data = JSON.parse(bytes.toString('utf8')); }
  catch (error) { throw new Error('Invalid default-options.json: ' + error.message); }
  const object = x => x !== null && typeof x === 'object' && !Array.isArray(x);
  if (!object(data) || !object(data.options) || !object(data.chatOptions) ||
      !Array.isArray(data.chatOptions.openChannels)) throw new Error('Missing options/chatOptions');
  if (!object(data.controlButtonsOptions) ||
      !Array.isArray(data.controlButtonsOptions.enabledButtons) ||
      !Array.isArray(data.controlButtonsOptions.disabledButtons)) throw new Error('Missing controlButtonsOptions');
  const hotkeys = data.hotkeyOptions;
  if (!object(hotkeys) || !object(hotkeys.hotkeySets) ||
      typeof hotkeys.currentHotkeySetName !== 'string' ||
      !object(hotkeys.hotkeySets[hotkeys.currentHotkeySetName])) throw new Error('Missing active hotkeyOptions');
  if (!Array.isArray(data.profiles) || !data.profiles.length) throw new Error('Missing profiles');
  for (const name of data.profiles) {
    const profile = hotkeys.hotkeySets[name];
    if (!object(profile) || !Array.isArray(profile.chatOn) || !Array.isArray(profile.chatOff) ||
        !object(profile.actionBarOptions) || !Array.isArray(profile.actionBarOptions.mappings))
      throw new Error('Invalid default hotkey profile: ' + name);
  }
  const dummy = data.DummyProfile;
  if (!object(dummy) || !Array.isArray(dummy.chatOn) || !Array.isArray(dummy.chatOff) ||
      !object(dummy.actionBarOptions) || !Array.isArray(dummy.actionBarOptions.mappings))
    throw new Error('Invalid DummyProfile');
  return { bytes: bytes.length, profiles: data.profiles.length };
}
if (require.main === module) {
  try {
    const file = process.argv[2] || path.join(__dirname, '../data/json/default-options.json');
    console.log('Default options validated:', validateDefaultOptions(fs.readFileSync(file)));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
module.exports = { validateDefaultOptions };
