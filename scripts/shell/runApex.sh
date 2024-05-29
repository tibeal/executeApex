# !/bin/bash
. scripts/shell/setEndpoint.sh

function executeApex {
    . scripts/config/env.cfg

    setEndpoint

    sf apex run --file $1 -o $SF_SESSION_ID

    status=$?

    sf config unset org-instance-url --global

    return $status
}

. scripts/config/env.cfg

executeApex $1
echo "status: $?"

while sleep $SF_RUN_APEX_DELAY;
do
    executeApex $1
    echo "status: $?"
done;