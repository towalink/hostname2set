#!/bin/bash

####################################################
### Add IPs of given hostname(s) to nftables set ###
####################################################

# Author: Dirk Henrici
# Creation: March 2024
# Last update: March 2024
# License: GPL3

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.


### Set initial/default values of variables ###

# Various settings controlling output behaviour
verbose=1
debug=0
syslog=0
logfile=
#logfile="/var/log/${0##*/}.log"

# A (for IPv4 set) or AAAA (for IPv6 set)
# Note that this setting needs to match the address type of the used set (otherwise: "Error: Could not resolve hostname: Name has no usable address")
addrtype=AAAA

# Table type and table name
tablename="inet filter"

# Name of the set to be used as target
setname=


########################
# Function definitions #
########################

# Prints a string in case verbose output is requested
function doOutputVerbose #(output)
{
  if [[ $verbose -ne 0 ]]; then
    echo "$1"
  fi
}

# Prints a string
function doOutput #(output, error)
{
  if [[ ${2:-0} -eq 1 ]]; then
    echo "$1" 2>&1
  else
    echo "$1"
  fi
  [[ $syslog -eq 0 ]] || logger "$0: $1"
}

# Prints an error message and exits the script
function exitWithError #(output)
{
  local erroutput="${1:-}"
  doOutput "$erroutput" 1
  trap '' ERR
  exit 1
}

# Printsuseage, an error message and exits the script
function exitWithUsageError #(output)
{
  printUsage
  echo
  exitWithError "$1"
}


# Prints an error message and exits the script
function exitWithTrapError #(lineno, output)
{
  local erroutput="${2:-}"
  if [ "$erroutput" == "" ]; then
    erroutput="Trapped shell error on line $1. See log file for error message. Aborting."
  fi
  exitWithError "$erroutput"
}

# Checks whether a command is available on the system and exits the script if not
function checkCommandAvailability #(command)
{
  command -v "$1" >/dev/null 2>&1 || exitWithError "The command '$1' cannot be found. Exiting."
}

# Prints information in the script usage (i.e. available command line parameters)
function printUsage
{
  echo -e "Usage: ${0##*/} [-d|--debug] [-t|--type A|AAAA] [[tabletype tablename] setname] hostname(s)\n"
  echo -e "  -h, --help        Prints usage info"
  echo -e "  -d, --debug       Enable debug output"
  echo -e "  -q, --quiet       Minimize output in case of success"
  echo -e "  -t, --type        'A' for IPv4 or 'AAAA' for IPv6"
  echo -e "  hostname(s)       one or more (comma-separated) hostnames for doing DNS query"
  echo
  echo -e "Example:"
  echo -e "  ${0##*/} inet filter myset myhost1.mydomain.com,myhost2.mydomain.com"
}


############################
# Prepare script execution #
############################

# Do not continue on error
# set -o errexit  # is the same as 'set -e'
# We do not use this as we evaluate results on our own

# Fail on "true | false"
set -o pipefail

# Exit if unset variable is used
set -o nounset  # is the same as 'set -u'

# Call function on error
trap 'exitWithTrapError $LINENO' ERR

### Initial actions ###

# Write output also to log file
if [ -n "${logfile}" ]; then
  exec > >(tee "${logfile}") 2>&1
fi

# Consider script parameters
textargs=()
while [ "${1:-}" != "" ]; # ${var:-unset} evaluates as unset if var is not set
do
    case $1 in
      -d  | --debug )       debug=1
                ;;
      -q  | --quiet )       verbose=0
                ;;
      -t  | --type )        shift; addrtype="${1:-}"
                ;;
      -h  | --help )        printUsage
                            exit
                ;;
      *)                    if [ "${1::1}" == "-" ]; then
                              exitWithUsageError "The parameter $1 is not allowed"
                            else
                              textargs+=("$1")
                            fi
                ;;
    esac
    shift
done

# Validate address type
if [ "$addrtype" != "A" ] && [ "$addrtype" != "AAAA" ]; then
  exitWithError "Type may only be 'A' (IPv4) or 'AAAA' (IPv6)"
fi
# Make sure hostname is provided
if [[ ${#textargs[@]} -eq 0 ]]; then
  exitWithUsageError "No hostname provided as command line argument"
fi
hostnames=${textargs[-1]}
# Set setname (if given)
if [[ ${#textargs[@]} -gt 1 ]]; then
  setname=${textargs[-2]}
fi
# Now setname must be set (either by config or by argument)
if [ -z "$setname" ]; then
  exitWithUsageError "No name for nftables set provided"
fi
# Set tablename (if given)
if [[ ${#textargs[@]} -eq 3 ]]; then
  exitWithUsageError "You need to provide tabletype, tablename, setname, and hostname(s)"
fi
# Set table type and table name (if given)
if [[ ${#textargs[@]} -gt 3 ]]; then
  tablename="${textargs[-4]} ${textargs[-3]}"
fi
if [[ ${#textargs[@]} -gt 4 ]]; then
  exitWithUsageError "Too many arguments provided"
fi
# Now tablename must be set (either by config or by arguments)
if [ -z "$tablename" ]; then
  exitWithUsageError "No tabletype and tablename of nftables set provided"
fi

# Check for root privileges
if [[ "$EUID" -ne 0 ]]; then
  exitWithError "You need to run this script with root privileges"
fi

# Switch on script debugging if requested
if [[ $debug -ne 0 ]]; then
  set -x
fi

# Check whether dig tool (part of bind-tools on Alpine) is installed
checkCommandAvailability /usr/bin/dig

for hostname in ${hostnames//,/ }
do
  # Do DNS lookup to get a list of IP addresses (filter cname aliases identified by trailing dot)
  addresses=$(dig +short -t "$addrtype" "$hostname" | grep -v '\.$')

  # Check for empty result
  if [ -z "$addresses" ]; then
    exitWithError "DNS lookup for [$hostname] failed"
  fi

  # Iterate over retrieved IP addresses and add them to set
  while IFS= read -r address; do
    if { [ "$addrtype" == "A" ] && [[ "$address" == *"."* ]]; } || { [ "$addrtype" == "AAAA" ] && [[ "$address" == *":"* ]]; } then
      doOutputVerbose "Adding address '$address' from hostname '$hostname' to set '$setname' to table '$tablename'"
      # Add or update entry in atomic operation (just adding would not update timeout if element already exists)
      nft -f - <<-EOF
	add element $tablename $setname { $address }
	delete element $tablename $setname { $address }
	add element $tablename $setname { $address }
	EOF
    else
      exitWithError "Unexpected output [$address]"
    fi
  done <<< "$addresses"
done
