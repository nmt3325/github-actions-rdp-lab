# Ephemeral GitHub Actions RDP desktops

On-demand desktops using **GitHub-hosted runners**. Choose Windows (native RDP), Ubuntu Linux (XRDP + XFCE), or experimental macOS (macrdp). Access is through **Tailscale only**; no internet-facing RDP port.

> **macOS warning:** macrdp needs the user-session Screen Recording and Accessibility permissions. GitHub-hosted runners normally cannot grant them interactively. This choice is a best-effort experiment and may not provide a usable desktop. Use a preconfigured self-hosted Mac for reliable macOS RDP.
>
> Sessions are temporary. Files, installed apps, and user data disappear when the job finishes. Do not use this for sensitive personal data.

## Set up once

1. Sign into [Tailscale](https://login.tailscale.com/admin/settings/keys), create an **ephemeral** and preferably tagged reusable auth key with suitable tailnet ACL permissions. Ensure it can accept incoming connections from your RDP client (and is pre-approved if device approval is enabled). Put it in this repository's **Settings → Secrets and variables → Actions → New repository secret** with the name `TAILSCALE_AUTHKEY`.
2. Create another repository Actions secret named `RDP_PASSWORD` containing a strong password (minimum 14 characters, with upper/lowercase letters, numbers and symbols). Do not use a password from another service.
3. Install and sign into Tailscale on your computer, tablet, or phone and confirm the device is allowed to access newly added devices.
4. Navigate to **Actions → On-demand RDP desktops → Run workflow**. Choose operating system and duration (default **360 minutes**, the GitHub-hosted maximum; setup time also counts).
5. Open the running job and its **Summary**, read the Tailscale IP address and username, then connect with any standard RDP client using the configured password.

## Connection information

| OS | Desktop / server | Username | Port |
| --- | --- | --- | --- |
| Windows | Windows RDP (local administrator) | `rdpuser` | 3389 |
| Linux | XFCE / XRDP | `rdpuser` | 3389 |
| macOS (experimental) | RDP + Apple Screen Sharing (VNC) | `rdpuser` (temporary local administrator) | RDP 3389/3390, VNC 5900 |

The Tailscale IP and username are written to the workflow Summary after setup. The password is never printed. When the requested time ends, or you cancel the workflow, access stops and the runner is deleted.

## Limitations and security

- GitHub-hosted jobs have a **six-hour maximum (360 minutes)**. The workflow defaults to this maximum, but installation and setup count toward the limit, so actual RDP access lasts slightly less than six hours.
- Only people authorized in your Tailscale network can reach the RDP service. Configure **Tailscale ACLs** to restrict access further. A tagged or ephemeral auth key is recommended; rotate it if compromised.
- Windows enforces RDP Network Level Authentication (NLA) and restricts incoming TCP 3389 to the current Tailscale address. Linux XRDP binds directly to the Tailscale address.
- The macOS experiment uses macrdp's normal PAM authentication with a temporary local `rdpuser` account created with the repository password and stored in the ephemeral macOS Keychain (`--keychain`); it listens only on the Tailscale address. Its security guarantees are **not equivalent** to standard local-account PAM authentication and it should not be used for sensitive workloads.
- Never add credentials to the repository, action arguments, or logs. Avoid running pull-request code in these privileged workflows.
- GitHub may restrict or bill for hosted-runner usage, and its Actions acceptable-use terms apply. This is not a permanent remote desktop hosting service.
- If the Microsoft Windows image or macOS screen-capture policies change, those environments may not be available. Troubleshoot the step logs.

## Files

- [Workflow](.github/workflows/rdp.yml)
- [Windows setup](scripts/windows-setup.ps1)
- [Linux setup](scripts/linux-setup.sh)
- [macOS experimental setup](scripts/macos-setup.sh)

## Stable hostname / MagicDNS

The runner requests `rdp-windows-00`, `rdp-linux-00`, or `rdp-macos-00` from the initial Tailscale connection. If `-00` is already taken, it tries `-01`, then `-02`, and so on. The actual allocated MagicDNS hostname (including your `*.ts.net` tailnet domain) appears in the job Summary. Set up [MagicDNS](https://tailscale.com/docs/features/magicdns) if needed.

**Machine names are predictable but IP addresses are not fixed.** If you start another session while a prior session is still attached, you get the next free suffix. After a session ends, the ephemeral Tailscale node is removed and its name can be reused. You cannot guarantee a single unchanged endpoint while multiple same-OS sessions are active.

## Windows password error

An `InvalidPasswordException` in the Windows account creation step indicates that the `RDP_PASSWORD` secret was rejected by Windows. Use a newly generated strong password (14+ characters, upper/lowercase letters, digits, symbols; without the username). The workflow checks the basic requirements and fails early with a clear message. You must change the secret yourself; it cannot be recovered or edited from this workflow.

## Files

- [Stable hostname allocator](scripts/allocate_hostname.py)

## Windows administrative privileges

On future Windows runs, `rdpuser` is added to the built-in local Administrators group (SID `S-1-5-32-544`) during setup. Sign in as `rdpuser` using the repository secret `RDP_PASSWORD`. For an administrator consent prompt, use `rdpuser` (or `.\rdpuser`), not the pre-existing `runneradmin` account. Existing running jobs do not pick up repository changes; start a new run to use this feature.

## macOS release binary and TCC

The macOS setup downloads the verified macrdp v0.9.11 Apple Silicon release tarball (SHA-256 pinned) rather than compiling from source on each run. It creates an ephemeral macOS `rdpuser` administrator account with the RDP_PASSWORD secret, verifies local authentication, and stores the same credential in the temporary runner Keychain. macrdp runs with `--keychain` and validates the account through PAM. `--skip-auth` is intentionally not used, as macrdp refuses it on a non-loopback listener. No public RDP port is exposed. macOS hosted runners may still lack Screen Recording/Accessibility approval: a successful TCP-listen check does **not** prove that the GUI is usable.

## macOS standard RDP port

In future macOS runs, `macrdp` listens on TCP **3389** (the RDP standard) on the Tailscale address, so clients can use the hostname without a port. A TCP relay on the same Tailscale address preserves compatibility with the former `:3390` port. This change does **not** affect already-running GitHub Actions sessions; those still require `:3390`. Both ports are only available to tailnet peers permitted by your Tailscale ACL.

## macOS VNC (Apple Screen Sharing, experimental)

New macOS runs also attempt to enable Apple's built-in Screen Sharing on TCP 5900 and check an RFB handshake, alongside the existing RDP service. Open `vnc://rdp-macos-00.<your-tailnet>.ts.net:5900` in the macOS Screen Sharing app or any compatible VNC viewer from your allowed Tailscale network. For Apple Screen Sharing, log in as `rdpuser` using the `RDP_PASSWORD` repository secret. For a legacy VNC viewer requesting only a VNC password, you may set an optional `VNC_PASSWORD` repository secret to **exactly 8 printable ASCII characters**. If unset, the first eight ASCII characters of `RDP_PASSWORD` are used as the VNC legacy password. Legacy VNC passwords are short; never expose VNC publicly and enforce a restrictive Tailscale policy.

**macOS caveat:** Apple restricts command-line Screen Sharing activation on macOS 12.1+, and access may be view-only or require interactive/MDM approval. A successful port/handshake test does not guarantee usable screen capture or keyboard/mouse input. An existing macOS run does not inherit these changes. [VNC setup script](scripts/macos-vnc-setup.sh).

### VNC black-screen finding (GitHub-hosted macOS 15)

A 2026-11-13 real VNC client test confirmed RFB 003.889, legacy VNC password authentication and a 3360×1080 framebuffer, but sampled framebuffer rectangles in multiple regions contained **only zero bytes (black)**. Therefore **this does not yet deliver an operable graphical macOS session on the tested GitHub-hosted macOS 15 runner**, despite a successful TCP listener and login. The `vnc-probe.yml` diagnostic workflow verifies authentication and sample pixels. This matches Apple's documented command-line/TCC restrictions: modern macOS requires local UI or MDM approval to enable usable Screen Sharing; the workflow cannot grant those permissions automatically. For reliable VNC use a self-hosted Mac with Screen Sharing permitted interactively or by MDM. This limitation does not affect Windows/Linux RDP functionality.
