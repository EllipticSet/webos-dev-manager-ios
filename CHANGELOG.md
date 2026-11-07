# Changelog

## 1.4.2

### Added
- In Apps › Available, each repository has a header: tap its name to hide or show its apps, so you can reach the next repository without scrolling past every app. Your choice is remembered.

### Changed
- Apps › Homebrew is now called Available.
- The Prepare a Developer Account step of the Developer Mode setup links to LG's Developer Mode guide, where you sign in or create your account.
- Checking off a step of the Developer Mode setup folds its instructions away, as in Dev Manager for desktop.
- Files shows Upload, New Folder, Select and Go To as separate buttons instead of one menu, and those that don't fit go to the system's overflow menu.
- In landscape on iPhone Duo's outer display, Manage TVs, Certificates, Settings and About are listed directly in the overflow menu instead of in a submenu.
- Terminal has a large title like the other tabs, and its text keeps a margin from the edges of the display.

### Fixed
- On iPhone Duo partially folded, the progress panel of an operation moves off the fold, as system alerts do: to the right half when you hold it like a book, and to the bottom half when it stands like a laptop.

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
