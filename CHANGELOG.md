# Changelog

## 1.4.1

### Changed
- Release notes on GitHub now include the changes of the version, taken from this changelog.

### Fixed
- Update checks keep the apps found on a repository's earlier pages when one of its later pages can't be loaded, instead of leaving out the whole repository.
- Update checks load linked manifests only for the apps installed on the TV, so large repositories no longer slow them down with requests for every app.

## 1.4

### Added
- **Repositories**: browse apps from the Non-Free Software repository and from your own repositories, next to the official webOS Homebrew catalog. Turn each one on or off from the new Repositories screen in Apps › Homebrew.
- **Add to TV**: offer a custom repository to Homebrew Channel, which opens on the TV with the address filled in for you to confirm with the remote.
- **Root Settings**: on TVs rooted with Homebrew Channel, turn Telnet, SSH Server, Block System Updates and Failsafe Mode on or off, and restart the TV to apply the changes (Info › Homebrew Channel).

### Changed
- Updates for installed apps are looked up in every repository you turned on.
- App icons are saved on the iPhone, so lists show them at once and offline. Settings › Clear Cache now removes icons and descriptions.
- The catalog reads repositories that publish all their apps on one page or that link their pages with `nextUrl`.
- Apps from repositories that link their manifest with `manifestUrl` can be installed and updated, and relative manifest and IPK addresses are supported.
- The project no longer sets a signing team, so local builds use your own.

### Fixed
- Restart TV reports connection and sign-in errors instead of showing the restart as done.
- A repository whose pages link back to each other no longer loads forever: browsing stops at a page already loaded, or after 50 pages.
- Pulling to refresh while a page is loading no longer mixes that page into the new list.

## 1.3

- First public release.
