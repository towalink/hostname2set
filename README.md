# hostname2set

Script that resolves a hostname to its corresponding IP addresses and adds these to an nftables set.

---

## Use case

At time of writing, nftables lacks the capability to add addresses to a set in the case that a hostname maps to more than a single IP address. This means that ``nft add element inet filter ipv4-temp-egress-web { myhost.myhost.example }`` fails in that case.

To make this work, this script does the name resolution using the ``dig`` tool. IP addresses matching the address type of the nftables set are then added to the set one after another.

This is useful for adding IP addresses to sets in a safe manner. With this, one can temporarily allow egress traffic to certain destinations, e.g. for loading updates.
```
   table inet filter {
        set ipv4-temp-egress-web {
            type ipv4_addr
            flags interval
            timeout 200s
        }
        ...
```

---

## Installation

Just download the shell script and make it executable (``chmod u+x hostname2set.sh``). Now you can test it:

```shell
./hostname2set.sh --help
```

The script used the ``dig`` utility to resolve hostnames to ip addresses. Make sure it is installed (already available in Debian default installation; ``apk add bind-tools`` for Alpine Linux).

---

## Quickstart

Execute the script to add IP addresses to a nftables set based on a given hostname:

```shell
./hostname2set.sh -t A inet filter ipv4-temp-egress-web myhost.myhost.example
```

---

## Reporting bugs

In case you encounter any bugs, please report the expected behavior and the actual behavior so that the issue can be reproduced and fixed.

---

## Developers

### Clone repository

Clone this repo to your local machine using `https://github.com/towalink/hostname2set.git`.

---

## License

[![License](http://img.shields.io/:license-gpl3-blue.svg?style=flat-square)](https://opensource.org/licenses/GPL-3.0)

- **[GPL3 license](https://opensource.org/licenses/GPL-3.0)**
- Copyright 2024 © <a href="https://github.com/towalink/hostname2set" target="_blank">Dirk Henrici</a>.
