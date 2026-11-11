### Fixed
- **The hooks and /kemory:status no longer import Python modules from the current directory.** Their Python programs ran as inline code, which puts the working directory first on the module path, so a file such as json.py in a project root would have run inside every hook. They now run from files in the plugin's scripts directory.
