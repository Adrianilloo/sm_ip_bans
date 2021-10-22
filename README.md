# sm_ip_bans
Syncs native SRCDS IP bans with a SQL database. This plugin safely allows to get rid of the default IP bans load/write commands (`exec banned_ip`, `writeip`) and local banlist file. The original intent was to automatically sync RCON bans externally, given that other advanced banning systems such as [SourceBans++](https://sbpp.dev/) don't support it concretely. Overall, the plugin provides these advantages:

- Supports both SQLite and MySQL via SM `databases.cfg`
- Syncs the bans with a remote machine (under MySQL)
- Saves timed IP bans (which aren't added to the `banned_ip.cfg` file by default) and expires them at the right time, without being affected by server restarts
- Syncs all legacy bans which were present in `banned_ip.cfg` by the time the plugin successfully connects to the configured database

To handle Steam ID based bans or non-native SRCDS IP bans in enhanced ways compared to the default, then you can (and should) use [SourceBans++](https://sbpp.dev/) instead.

## Configuration
The only thing you need to set up is the database connection. The plugin first checks non-strictly for a `databases.cfg` configuration entry named `"ip_bans"` and, only if it isn't present, it requires the `"default"` section instead.

## Contributing
PRs, suggestions and issues reports are welcome. Please, note that the idea of this plugin was to cover the default lack of support in a sufficient way. If you wish to provide additional components such as a Web interface for easy management, you're on your own.
