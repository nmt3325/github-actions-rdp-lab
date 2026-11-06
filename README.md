# Ephemeral GitHub Actions RDP desktops

On-demand desktops using **GitHub-hosted runners**. Choose Windows (native RDP), Ubuntu Linux (XRDP + XFCE), or experimental macOS (macrdp). Access is through **Tailscale only**; no internet-facing RDP port.

> **macOS warning:** macrdp needs the user-session Screen Recording and Accessibility permissions. GitHub-hosted runners normally cannot grant them interactively. This choice is a best-effort experiment and may not provide a usable desktop. Use a preconfigured self-hosted Mac for reliable macOS RDP.
>
> Sessions are temporary. Files, installed apps, and user data disappear when the job finishes. Do not use this for sensitive personal data.

## Set up once

1. Sign into [Tailscale](https://login.tailscale.com/admin/settings/keys), create an **ephemeral** and preferably tagged reusable auth key with suitable tailnet ACL permissions. Ensure it can accept incoming connections from your RDP client (and is pre-approved if device approval is enabled). Put it in this repository's **Settings → Secrets and variables → Actions → New repository secret** with the name `TAILSCALE_AUTHKEY`.
2. Create another repository Actions secret named `RDP_PASSWORD` containing a strong password (minimum 14 characters, with upper/lowercase letters, numbers and symbols). Do not use a password from another service.
3. Install and sign into Tailscale on your computer, tablet, or phone and confirm the device is allowed to access newly added devices.
4. Navigate to **Actions → On-demand RDP desktops → Run workflow**. Choose operating system and duration (the default is **300 minutes, the longest option**).
5. Open the running job and its **Summary**, read the Tailscale IP address and username, then connect with any standard RDP client using the configured password.

## Connection information

| OS | Desktop / server | Username | Port |
| --- | --- | --- | --- |
| Windows | Windows RDP | `rdpuser` | 3389 |
| Linux | XFCE / XRDP | `rdpuser` | 3389 |
| macOS (experimental) | macrdp / virtual display | `runner` (usually; see summary) | 3390 |

The Tailscale IP and username are written to the workflow Summary after setup. The password is never printed. When the requested time ends, or you cancel the workflow, access stops and the runner is deleted.

## Limitations and security

- GitHub-hosted jobs have a **six-hour maximum**. Setup and cleanup take time, so this workflow limits the selectable RDP hold time to five hours and the job timeout to 355 minutes.
- Only people authorized in your Tailscale network can reach the RDP service. Configure **Tailscale ACLs** to restrict access further. A tagged or ephemeral auth key is recommended; rotate it if compromised.
- Windows enforces RDP Network Level Authentication (NLA) and restricts incoming TCP 3389 to the current Tailscale address. Linux XRDP binds directly to the Tailscale address.
- The macOS experiment uses macrdp's documented test-only `--skip-auth` with a password file, bound to the Tailscale address. Its security guarantees are **not equivalent** to standard local-account PAM authentication and it should not be used for sensitive workloads.
- Never add credentials to the repository, action arguments, or logs. Avoid running pull-request code in these privileged workflows.
- GitHub may restrict or bill for hosted-runner usage, and its Actions acceptable-use terms apply. This is not a permanent remote desktop hosting service.
- If the Microsoft Windows image or macOS screen-capture policies change, those environments may not be available. Troubleshoot the step logs.

## Files

- [Workflow](.github/workflows/rdp.yml)
- [Windows setup](scripts/windows-setup.ps1)
- [Linux setup](scripts/linux-setup.sh)
- [macOS experimental setup](scripts/macos-setup.sh)
