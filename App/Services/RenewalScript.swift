import Foundation

/// Generates a shell script for cron on a computer that's always on, because iOS can't renew on a schedule reliably.
enum RenewalScript {
  /// Contains only the session token, not the SSH key, so a leaked script can't open the TV.
  static func make(deviceName: String, token: String) -> String {
    """
    #!/bin/sh
    # Renews the webOS Developer Mode session of "\(deviceName.replacingOccurrences(of: "\n", with: " "))".
    # Schedule it with cron, for example once a day. Requires curl.
    # The token below allows renewing this TV's session: keep this file private.

    SESSION_TOKEN=\(token.shellQuoted)

    RESPONSE=$(curl --max-time 30 --fail --silent --show-error \\
      "https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=$SESSION_TOKEN") || exit $?

    case "$RESPONSE" in
      *'"result":"success"'*|*'"result" : "success"'*) echo "$RESPONSE" ;;
      *) echo "Renewal failed: $RESPONSE" >&2; exit 1 ;;
    esac

    """
  }

  static func fileName(deviceName: String) -> String {
    let safe = deviceName.replacing(/[^A-Za-z0-9._-]/, with: "_")
    return "renew-devmode-\(safe).sh"
  }
}
