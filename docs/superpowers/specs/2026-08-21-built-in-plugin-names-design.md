# Built-in Plugin Names Design

## Goal

Remove the `demo-` prefix and the demo classification from all built-in plugins.
Combine related display effects into one `screen-effects.js` plugin.

## Catalog

The catalog contains built-in plugins. It does not classify plugins as stock or demo.
Each catalog row contains `filename`, `highlighted`, and `category`.

All built-in plugin filenames use their functional name. For example,
`demo-calculator.js` becomes `calculator.js`.

The Featured star remains the only special catalog status.

## Screen Effects

The new `screen-effects.js` plugin replaces these bundled files:

- `demo-night-vision.js`
- `demo-gamma-black.js`
- `demo-display-modes.js`

The combined plugin keeps these commands:

- Toggle Night Vision
- Toggle Extra Dark
- Toggle Invert Display
- Toggle Night Shift
- Night Shift 60%
- Toggle True Tone
- Toggle Grayscale

The Brightness, Appearance, and Color Picker plugins remain separate.

## Installed Plugin Migration

Macotron runs the migration before it loads plugins.

For each one-to-one rename, Macotron moves `demo-<name>.js` to `<name>.js`.
Macotron does not move a file when the destination exists.
This rule prevents data loss.

When a move succeeds, Macotron updates all filename-based state:

- plugin settings
- disabled plugin names
- command shortcut IDs
- keyboard shortcut IDs
- launcher favorite IDs
- approved plugin hashes

Macotron does not migrate the three files that became Screen Effects.
Existing copies remain installed.
The catalog offers `screen-effects.js` as a separate plugin.
This choice can produce duplicate commands until the user removes the old files.

## Documentation and Tests

The examples README uses the new filenames and the term built-in plugins.
Tests use the new filenames and remove Demo from test names where practical.
Site examples and design documents use the new filenames.

Migration tests cover file moves, destination conflicts, settings, shortcuts,
favorites, disabled plugins, and trust hashes.
