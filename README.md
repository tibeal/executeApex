# Execute Apex in loop

Get your org info from `Setup > My Domain`
![alt text](https://github.com/tibeal/images/blob/master/image-16.png?raw=true)

Then the env vars like (file scripts/config/env.cfg):
```cfg
SF_INSTANCE=
SF_DOMAIN=customer-enterprise-782-dev-ed.scratch.my.salesforce.com
SF_SESSION_ID="my-scratch"
SF_RUN_APEX_DELAY=3
```

Then run the shell script like the following
```apex
scripts/shell/runApex.sh "scripts/apex/createExpirationTransactions.apex"
```