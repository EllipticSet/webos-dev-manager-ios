# Changelog

## 1.5.0

### Added
- **Italian**: the whole app is available in Italian, including error messages, Developer Mode setup and the permission prompts. It follows the language set on the iPhone, or the one chosen for Dev Manager in Settings › Apps. App names and descriptions from repositories, and messages from the TV, stay as their source provides them.
- A Delete Certificate button at the bottom of a certificate's page. As when swiping it in the list, a certificate that a TV signs in with can't be deleted until that TV uses another sign-in method.
- Terminal shows the open sessions in a bar at the top, so you can see which one is in use and how many are open, and switch between them with a tap. A dot shows whether each one is connecting, connected or disconnected.

### Changed
- Confirmations such as Uninstall, Remove, Delete, Replace and Clear Log appear as an alert in the center of the screen instead of a bubble that, on wider screens, didn't line up with the button you tapped.
- Confirmations show the name of the TV, certificate or file in the title, where a long name wraps, and keep the button short.
- On iPhone Duo partially folded, confirmations, the certificate messages and the progress panel of an operation appear on the right half when you hold it like a book, and on the top half when it stands like a laptop.
- A terminal session closes by itself when its shell ends, such as after `exit`, instead of showing "Session ended" with Reconnect, and the next open session takes its place. When the connection fails, the error and Reconnect still appear.
- The message shown when deleting a certificate that a TV signs in with explains that the TV couldn't connect without it.
- The project's tests check that every Italian string keeps the placeholders of its English text, so a translation can't show wrong values.

### Fixed
- With a passcode on, the biometry setting and the lock screen name the device's own biometry, such as Touch ID on iPhone Duo, instead of "Face ID or Touch ID", also when it isn't set up yet.
- In the sidebar on iPhone Duo's inner display, choosing another section now works after opening a page inside a section, such as an app's page, Root Settings or a crash report.
- Canceling a removal started by swiping a row no longer hides the row until the list reloads.

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
