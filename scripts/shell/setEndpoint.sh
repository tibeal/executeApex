# !/bin/bash
. scripts/config/env.cfg

function setEndpoint {
    . scripts/config/env.cfg

    if [ -z ${SF_DOMAIN} ];
    then
        echo "SF_DOMAIN is unset";
        if [ -z ${SF_INSTANCE} ];
        then
            echo "ERROR: neither SF_INSTANCE or SF_DOMAIN is set";
            return 1
        else
            echo "SF_DOMAIN is set to '$SF_INSTANCE'";
            sf config set org-instance-url="https://$SF_INSTANCE.salesforce.com"
        fi
    else
        echo "SF_DOMAIN is set to '$SF_DOMAIN'";
        sf config set org-instance-url="https://$SF_DOMAIN"
    fi
}