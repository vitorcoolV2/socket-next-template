# Pi-hole DNS Management

Pi-hole provides network-wide DNS and ad-blocking. In this stack, it is also used as a dynamic DNS registry for all internal services.

## Service Integration

Every service in the stack is accessible via `<service>.$DOMAIN`. The `ph_api dns sync` command ensures these records are always up to date.

## Usage

Source the library:

```bash
source devops/pihole/pihole_lib.sh

ph_api open        # Open KeePass and restore password
ph_api auth        # Authenticate to Pi-hole API
ph_api close       # Logout

ph_api dns get_records      # List DNS records
ph_api dns add <ip> <host> # Add DNS entry
ph_api dns remove <host>   # Remove DNS entry
ph_api dns sync            # Sync all <service>.$DOMAIN entries
ph_api dns expected        # Show expected DNS records

ph_api password rotate     # Rotate web password
```

## DNS Sync Logic

The `sync` command compares "Expected" records (derived from the service list) against "Actual" records in Pi-hole:

- **Removes**: Entries found in Pi-hole that are not in the expected list.
- **Adds**: Entries in the expected list that are missing from Pi-hole.
- **Updates**: Entries pointing to the wrong IP address.
