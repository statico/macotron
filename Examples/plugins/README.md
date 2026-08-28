# Built-in plugins

Copy into your Macotron workdir `plugins/` to try. Most register launcher commands.

Built-in plugins use only `macotron.*` and Apple-shipped tools. They do not need Homebrew or other extra apps.

Plugin variables are lost on every reload and every restart, so a plugin saves
what the user chose in `localStorage` and claims it back at load — see
`fan.js`, `power.js`, `pomodoro.js`. Options declared in `macotron.plugin()`
are saved by the host already.

Each plugin declares its own title and description in its `macotron.plugin({...})`
header. Read the file for what it does.
