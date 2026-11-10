### Fixed
- **Credential resolution and the hook helpers no longer import Python modules from the current directory.** They ran their Python as inline code, which puts the working directory first on the import path, so a `json.py` in a project root ran inside the program that holds the refresh token. They now run from files in the plugin's own directory.
