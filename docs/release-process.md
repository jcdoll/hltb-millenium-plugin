# Release Process

This document describes how to release the plugin to the Millennium Plugin Database.

## Prerequisites

Before submitting:
- Plugin builds successfully with `npm run build`
- `plugin.json` and `package.json` have matching version numbers
- All changes are committed and pushed to the main branch

## Initial Submission

1. Clone the PluginDatabase fork:
   ```bash
   git clone https://github.com/jcdoll/PluginDatabase
   cd PluginDatabase
   ```

2. Add the plugin as a submodule:
   ```bash
   cd plugins
   git submodule add https://github.com/jcdoll/hltb-millennium-plugin hltb-millennium-plugin
   cd ..
   git add .
   git commit -m "Add HLTB for Steam plugin"
   git push
   ```

3. Open a Pull Request from `jcdoll/PluginDatabase` to `SteamClientHomebrew/PluginDatabase`

4. Wait for maintainer code review and approval

## Updating an Existing PR

If you have an open PR and need to update the submodule to point to a newer commit:

1. In your PluginDatabase checkout, update the submodule to the latest:
   ```bash
   cd plugins/hltb-millennium-plugin
   git fetch origin
   git checkout origin/main
   cd ../..
   ```

2. Commit and push the updated submodule pointer:
   ```bash
   git add plugins/hltb-millennium-plugin
   git commit -m "Update hltb-millennium-plugin to latest"
   git push
   ```

The PR will automatically reflect the new submodule commit.

## Publishing Updates

When releasing a new version:

1. Update version in both `plugin.json` and `package.json` (must match)

2. Run `npm install` to update package-lock.json

3. Build and test the plugin locally:
   ```bash
   npm run build
   ```

4. Commit and push changes to the plugin repository

5. Run the "Create Release" GitHub Action:
   - Go to Actions > Create Release > Run workflow
   - Enter the version number (must match all three files)
   - The workflow validates versions match, builds, and creates a GitHub release

6. Update the submodule in PluginDatabase:
   ```bash
   cd PluginDatabase/plugins/hltb-millennium-plugin
   git pull origin main
   cd ../..
   git add .
   git commit -m "Update HLTB for Steam to vX.X.X"
   git push
   ```

7. Open a new Pull Request to `SteamClientHomebrew/PluginDatabase`

Each update requires maintainer review before reaching users.

## Notes

- The PluginDatabase pins your plugin to a specific commit
- Updates are not automatic; each version requires a PR
- Users install from https://steambrew.app/plugins, not directly from the database
- All code changes are audited for security before distribution
