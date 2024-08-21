#!/bin/bash
set -x

shopt -s expand_aliases

# ASSUMES elementsd IS ALREADY RUNNING

######################################################
#                                                    #
#    SCRIPT CONFIG - PLEASE REVIEW BEFORE RUNNING    #
#                                                    #
######################################################

# Amend the following:
NAME="Decentralized Pix"
TICKER="DePix"
# Do not use a domain prefix in the following:
DOMAIN="depix.info"
# Issue 100 assets, dependant on PRECISION when viewed from
# applications using Asset Registry data.
ASSET_AMOUNT=1000000.00000000
# Issue 1 reissuance token using the satoshi unit, unaffected by PRECISION.
TOKEN_AMOUNT=0.00000100

# Amend the following if needed:
PRECISION=8

# Optional collection parameter. Set to "" to ignore:
COLLECTION=""

# Asset registry url
# When using test-net replace to
# https://assets-testnet.blockstream.info/
ASSET_REGISTRY_URL="https://assets.blockstream.info/"

# Don't change the following:
VERSION=0

# Change the following to point to your elements-cli binary and liquid live data directory (default is .elements).
alias e1-cli="elements-cli -datadir=$HOME/.elements"

# We will hash using sha256sum if available, openssl otherwise (other options are available)
which sha256sum >/dev/null 2>&1 && alias sha256hash="sha256sum | sed 's/ .*//g'" || alias sha256hash="openssl dgst -sha256 | sed 's/.*= //g'"

##############################
#                            #
#    END OF SCRIPT CONFIG    #
#                            #
##############################

# Exit on error
set -o errexit

# We validate characters in the domain
echo $DOMAIN| grep -q '[^a-z0-9\.-]' && RV=$? || RV=$?
if [ $RV -eq 0 ];then
    echo "invalid chars detected in the domain, exiting...."
    exit -1
fi

# We will be using the issueasset command and the contract_hash argument:
# issueasset <assetamount> <tokenamount> <blind> <contract_hash>

# As we need to sign the deletion request message later we need
# a legacy address. If you prefer to generate a pubkey and sign
# outside of Elements you can use a regular address instead.
NEWADDR=$(e1-cli getnewaddress "" legacy)

VALIDATEADDR=$(e1-cli getaddressinfo $NEWADDR)

PUBKEY=$(echo $VALIDATEADDR | jq -r '.pubkey')

ASSET_ADDR=$NEWADDR

NEWADDR=$(e1-cli getnewaddress "" legacy)

TOKEN_ADDR=$NEWADDR

# Create the contract and calculate the contract hash
# The contract is formatted for use in the Blockstream Asset Registry:
if [ "$COLLECTION" = "" ]; then
    CONTRACT='{"entity":{"domain":"'$DOMAIN'"},"issuer_pubkey":"'$PUBKEY'","name":"'$NAME'","precision":'$PRECISION',"ticker":"'$TICKER'","version":'$VERSION'}'
else
    CONTRACT='{"collection":"'$COLLECTION'","entity":{"domain":"'$DOMAIN'"},"issuer_pubkey":"'$PUBKEY'","name":"'$NAME'","precision":'$PRECISION',"ticker":"'$TICKER'","version":'$VERSION'}'
fi

CONTRACT_HASH=$(echo -n "${CONTRACT}" | sha256hash)

# Reverse the hash --- expects an even length
TEMP=$CONTRACT_HASH
LEN=${#TEMP}
until [ $LEN -eq "0" ]; do
    END=${TEMP:(-2)}
    CONTRACT_HASH_REV="$CONTRACT_HASH_REV$END"
    TEMP=${TEMP::$((${#TEMP} - 2))}
    LEN=$((LEN-2))
done

# Issue the asset and pass in the contract hash
IA=$(e1-cli issueasset $ASSET_AMOUNT $TOKEN_AMOUNT false $CONTRACT_HASH_REV)

# Details of the issuance...
ASSET=$(echo $IA | jq -r '.asset')
TOKEN=$(echo $IA | jq -r '.token')
ISSUETX=$(echo $IA | jq -r '.txid')

#####################################
#                                   #
#    ASSET REGISTRY FILE OUTPUTS    #
#                                   #
#####################################

# Output the proof file - you need to place this on your domain.
echo "Authorize linking the domain name $DOMAIN to the Liquid asset $ASSET" > liquid-asset-proof-$ASSET

# Create the bash script to run after you have placed the proof file on your domain
# that will call the registry and request the asset is registered.
echo "curl $ASSET_REGISTRY_URL --data-raw '{\"asset_id\":\"$ASSET\",\"contract\":$CONTRACT}'" > register_asset_$ASSET.sh

# Create the bash script to delete the asset from the registry (if needed later)
PRIV=$(e1-cli dumpprivkey $ASSET_ADDR)
SIGNED=$(e1-cli signmessagewithprivkey $PRIV "remove $ASSET from registry")
echo "curl -X DELETE $ASSET_REGISTRY_URL$ASSET -H 'Content-Type: application/json' -d '{\"signature\":\"$SIGNED\"}'" > delete_asset_$ASSET.sh

# Stop the daemon
#e1-cli stop
#sleep 10

echo "Completed without error"
