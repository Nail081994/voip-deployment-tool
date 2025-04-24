# voip-deployment-tool

Automated installation and initial configuration script for a single-server RTU 2.3* system on **Debian 10 (Buster)**.

> This script is designed for internal infrastructure deployments with limited external access. It configures the base system, required services, and handles licensing preparation.

---

## ⚠️ Disclaimer

> This script is intended as an example and reference for automation.  
> While it is functional, it **requires a proprietary VOIP software distribution** provided by our company.  
> Without the corresponding binary distribution, this installer will not operate as intended.

---

## Features

- Installs system packages & dependencies
- Sets up basic network & DNS
- Configures iptables with secure defaults
- Applies initial configs (SIP, DB, management)
- Uses PHP SOAP API to populate RTU entities
- Prepares licensing archive for RTU activation

---

## Usage

Run **as root**:

```bash
sudo ./rtu5_installator.sh -A
```

### Available Arguments

| Flag | Description |
|------|-------------|
| `-A` | Run full installation (all components) |
| `-T` | Prepare system archive for license request |
| `-D` | Check DNS and install dependencies |

---

## Installation Flow

1. Select IP address (auto or prompt)
2. Check internet and update apt sources
3. Install packages: `curl`, `ntp`, `dnsutils`, etc.
4. Setup firewall with iptables rules
5. Configure RTU zones, modules, and API endpoints
6. Generate secure credentials & apply to config files
7. Trigger PHP SOAP API requests to MTT server

---

## Licensing

To generate a system archive for requesting a license:

```bash
sudo ./rtu5_installator.sh -T
```

This creates a `.tar.bz2` archive with hardware info.  
Send it to `license@your_mail.org` with your company name.

---

## Key Paths

| Purpose           | Path                                                  |
|------------------|-------------------------------------------------------|
| Variable File     | `/usr/share/rtu5_installator/vars_installator.sh`     |
| License Storage   | `/usr/share/rtu5_installator/licenses`                |
| Log Directory     | (prompted or default to script's launch directory)    |

---

## Sample Output

```bash
[ INFO ] DNS successfully configured.
[ INFO ] Debian repositories accessible. Installing required packages...
[ INFO ] Selected IP: 192.168.1.55
[ INFO ] Performing API requests to preconfigure SIP modules...
```

---

## Notes

- Tested on **Debian 10 Buster** only
- Must be run as `root`
- Includes inline PHP SOAP script for RTU API access
- No graphical UI; fully terminal-interactive

---

## Tips

- Make sure `php`, `dmidecode`, and `apt` are installed
- If running in an isolated network, manually install `.deb` dependencies

---

## Support

For questions or license activation follow-ups, contact:

- `license@your_mail.org`
- [Helpdesk portal](https://helpdesk.satel.org) (08:00–17:00 business days)

---

## Author Notes

This script was designed to simplify deployment in production-like or airgapped environments. It minimizes manual input, validates network and system readiness, and integrates with external APIs for post-install provisioning.

---
